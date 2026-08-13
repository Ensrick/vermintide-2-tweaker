# Shared machine-global VMB/Stingray transaction lease (issue #1180).
#
# ship.ps1 owns this continuously across build, parity, deploy, release,
# upload, Workshop verification, card refresh, and claim finalization. A child
# launcher must independently validate this live parent and held mutex;
# inherited environment text alone is never authority.

$script:VmbTransactionMutexName = 'Global\Ensrick.VMBLauncher.Transaction.v1'
$script:VmbTransactionLeaseIdEnvironmentVariable = 'VMBLAUNCHER_TRANSACTION_LEASE_ID'
$script:VmbTransactionOwnerPidEnvironmentVariable = 'VMBLAUNCHER_TRANSACTION_OWNER_PID'
$script:VmbTransactionOwnerStartEnvironmentVariable = 'VMBLAUNCHER_TRANSACTION_OWNER_START_UTC_TICKS'
$script:VmbTransactionRecordPathEnvironmentVariable = 'VMBLAUNCHER_TRANSACTION_RECORD_PATH'

if (-not ('VmbTransactionMutexHolder' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

public sealed class VmbTransactionMutexHolder : IDisposable
{
    private readonly ManualResetEvent _release = new ManualResetEvent(false);
    private readonly ManualResetEvent _abandon = new ManualResetEvent(false);
    private readonly ManualResetEvent _ready = new ManualResetEvent(false);
    private readonly Thread _thread;
    private readonly string _name;
    private Mutex _mutex;
    private bool _closed;
    private Exception _failure;
    private static readonly object RetainedSync = new object();
    private static readonly Dictionary<string, Mutex> Retained = new Dictionary<string, Mutex>(StringComparer.Ordinal);
    private static int _activeThreads;
    public bool WasAbandoned { get; private set; }
    public static int ActiveThreadCount { get { return Volatile.Read(ref _activeThreads); } }

    private VmbTransactionMutexHolder(string name, int timeoutMilliseconds)
    {
        _name = name;
        _thread = new Thread(() => Run(name, timeoutMilliseconds));
        _thread.IsBackground = true;
        _thread.Name = "VMB transaction owner";
        _thread.Start();
        _ready.WaitOne();
        if (_failure != null) {
            Dispose();
            throw new InvalidOperationException(_failure.Message, _failure);
        }
        ReleaseRetained(name);
    }

    public static VmbTransactionMutexHolder Acquire(string name, int timeoutMilliseconds)
    {
        return new VmbTransactionMutexHolder(name, timeoutMilliseconds);
    }

    private void Run(string name, int timeoutMilliseconds)
    {
        Interlocked.Increment(ref _activeThreads);
        try {
            var mutex = new Mutex(false, name);
            _mutex = mutex;
                bool acquired;
                try { acquired = mutex.WaitOne(timeoutMilliseconds); }
                catch (AbandonedMutexException) { acquired = true; WasAbandoned = true; }
                if (!acquired)
                    throw new TimeoutException("Another VMB/Stingray transaction held the machine mutex for more than " + timeoutMilliseconds + " ms.");
                _ready.Set();
                int completion = WaitHandle.WaitAny(new WaitHandle[] { _release, _abandon });
                if (completion == 0) mutex.ReleaseMutex();
        }
        catch (Exception ex) {
            _failure = ex;
            _ready.Set();
        }
        finally { Interlocked.Decrement(ref _activeThreads); }
    }

    public void Dispose()
    {
        if (_closed) return;
        _closed = true;
        _release.Set();
        if (_thread != null && _thread.IsAlive && !_thread.Join(10000))
            throw new TimeoutException("Transaction mutex thread did not stop.");
        if (_mutex != null) _mutex.Dispose();
        _release.Dispose();
        _abandon.Dispose();
        _ready.Dispose();
    }

    public void Abandon()
    {
        if (_closed) throw new ObjectDisposedException("VmbTransactionMutexHolder");
        _closed = true;
        _abandon.Set();
        if (_thread != null && _thread.IsAlive && !_thread.Join(10000))
            throw new TimeoutException("Transaction mutex thread did not abandon ownership.");
        if (_failure != null) throw new InvalidOperationException(_failure.Message, _failure);
        if (_mutex == null) throw new InvalidOperationException("Transaction mutex handle was unavailable.");
        lock (RetainedSync) {
            Mutex previous;
            if (Retained.TryGetValue(_name, out previous)) previous.Dispose();
            Retained[_name] = _mutex;
        }
        _release.Dispose();
        _abandon.Dispose();
        _ready.Dispose();
    }

    private static void ReleaseRetained(string name)
    {
        lock (RetainedSync) {
            Mutex retained;
            if (Retained.TryGetValue(name, out retained)) {
                Retained.Remove(name);
                retained.Dispose();
            }
        }
    }
}

public static class VmbTransactionProcessTreeGuard
{
    private static readonly object Sync = new object();
    private static IntPtr _job = IntPtr.Zero;
    private static string _jobName;
    private const uint KillOnClose = 0x00002000;

    public static string Ensure()
    {
        lock (Sync) {
            if (_job != IntPtr.Zero) return _jobName;
            using (Process currentIdentity = Process.GetCurrentProcess()) {
                _jobName = "Global\\Ensrick.VMBLauncher.Transaction.Process." + currentIdentity.Id + "." + currentIdentity.StartTime.ToUniversalTime().Ticks + "." + Guid.NewGuid().ToString("N");
            }
            IntPtr job = CreateJobObject(IntPtr.Zero, _jobName);
            if (job == IntPtr.Zero) Throw("create process-tree containment job");
            try {
                JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                info.BasicLimitInformation.LimitFlags = KillOnClose;
                int size = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
                IntPtr memory = Marshal.AllocHGlobal(size);
                try {
                    Marshal.StructureToPtr(info, memory, false);
                    if (!SetInformationJobObject(job, 9, memory, (uint)size)) Throw("configure process-tree containment job");
                }
                finally { Marshal.FreeHGlobal(memory); }
                using (Process current = Process.GetCurrentProcess()) {
                    if (!AssignProcessToJobObject(job, current.Handle))
                        Throw("assign transaction owner to process-tree containment job");
                }
                _job = job; // deliberately process-lifetime: closing it kills current descendants
                return _jobName;
            }
            catch {
                CloseHandle(job);
                throw;
            }
        }
    }

    public static void WaitForDrained(string jobName, int timeoutMilliseconds)
    {
        const uint JOB_OBJECT_QUERY = 0x0004;
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMilliseconds);
        while (true) {
            uint active;
            IntPtr job = OpenJobObject(JOB_OBJECT_QUERY, false, jobName);
            if (job == IntPtr.Zero) {
                int error = Marshal.GetLastWin32Error();
                if (error == 2) return;
                Throw("open abandoned transaction process-tree job");
            }
            try { active = QueryActiveCount(job); }
            finally { CloseHandle(job); }

            // Jobs do not ordinarily become signalled when ActiveProcesses is
            // zero. Close every temporary query handle before waiting again:
            // retaining it could prevent a dead owner's last KILL_ON_JOB_CLOSE
            // handle from closing and therefore delay descendant termination.
            if (active == 0) return;
            if (DateTime.UtcNow >= deadline)
                throw new TimeoutException("Abandoned transaction process tree retained " + active + " active process(es) beyond recovery timeout.");
            Thread.Sleep(20);
        }
    }

    public static void TerminateAndWaitForResidualDescendants(int timeoutMilliseconds)
    {
        using (Process current = Process.GetCurrentProcess()) {
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMilliseconds);
            while (true) {
                uint[] active = QueryActive(_job);
                System.Collections.Generic.List<uint> residual = new System.Collections.Generic.List<uint>();
                foreach (uint pid in active) if (pid != (uint)current.Id) residual.Add(pid);
                if (residual.Count == 0) return;
                foreach (uint pid in residual) {
                    try { using (Process p = Process.GetProcessById((int)pid)) {
                        if (!p.HasExited) {
                            bool belongs;
                            if (!IsProcessInJob(p.Handle, _job, out belongs)) Throw("authenticate residual process job membership");
                            if (belongs) p.Kill();
                        }
                    } }
                    catch (ArgumentException) { }
                }
                if (DateTime.UtcNow >= deadline)
                    throw new TimeoutException("Transaction process tree retained descendants; mutex was not released.");
                Thread.Sleep(20);
            }
        }
    }

    private static uint[] QueryActive(IntPtr job)
    {
        const int bytes = 65536;
        IntPtr memory = Marshal.AllocHGlobal(bytes);
        try {
            uint returned;
            if (!QueryInformationJobObject(job, 3, memory, bytes, out returned)) Throw("query transaction process-tree membership");
            int active = Marshal.ReadInt32(memory, 4);
            uint[] result = new uint[active];
            for (int i = 0; i < active; i++) result[i] = (uint)Marshal.ReadIntPtr(memory, 8 + i * IntPtr.Size).ToInt64();
            return result;
        }
        finally { Marshal.FreeHGlobal(memory); }
    }

    private static uint QueryActiveCount(IntPtr job)
    {
        int size = Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION));
        IntPtr memory = Marshal.AllocHGlobal(size);
        try {
            uint returned;
            if (!QueryInformationJobObject(job, 1, memory, size, out returned))
                Throw("query abandoned transaction process-tree accounting");
            JOBOBJECT_BASIC_ACCOUNTING_INFORMATION value =
                (JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)Marshal.PtrToStructure(
                    memory, typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION));
            return value.ActiveProcesses;
        }
        finally { Marshal.FreeHGlobal(memory); }
    }

    public static IntPtr CreateOrdinarilyEmptiedJobForTest(string jobName)
    {
        if (!String.Equals(Environment.GetEnvironmentVariable("VMBLAUNCHER_TRANSACTION_TEST_MODE"), "1", StringComparison.Ordinal))
            throw new InvalidOperationException("The planted Job helper is test-only.");
        IntPtr job = CreateJobObject(IntPtr.Zero, jobName);
        if (job == IntPtr.Zero) Throw("create planted empty Job fixture");
        Process child = null;
        try {
            string command = Environment.GetEnvironmentVariable("ComSpec");
            if (String.IsNullOrWhiteSpace(command))
                command = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
            child = Process.Start(new ProcessStartInfo {
                FileName = command,
                Arguments = "/d /c ping -n 2 127.0.0.1 >nul",
                UseShellExecute = false,
                CreateNoWindow = true
            });
            if (child == null) throw new InvalidOperationException("Could not start planted Job fixture child.");
            if (!AssignProcessToJobObject(job, child.Handle)) Throw("assign planted Job fixture child");
            if (!child.WaitForExit(10000)) throw new TimeoutException("Planted Job fixture child did not exit.");
            DateTime deadline = DateTime.UtcNow.AddSeconds(5);
            while (QueryActiveCount(job) != 0) {
                if (DateTime.UtcNow >= deadline)
                    throw new InvalidOperationException("Planted Job fixture did not ordinarily drain to zero active processes.");
                Thread.Sleep(20);
            }
            child.Dispose();
            return job;
        }
        catch {
            if (child != null) {
                try { if (!child.HasExited) child.Kill(); } catch { }
                child.Dispose();
            }
            CloseHandle(job);
            throw;
        }
    }

    public static void CloseTestJob(IntPtr job)
    {
        if (job != IntPtr.Zero) CloseHandle(job);
    }

    private static void Throw(string operation)
    {
        throw new InvalidOperationException("Could not " + operation + " (Win32 " + Marshal.GetLastWin32Error() + "); refusing mutation.");
    }

    [StructLayout(LayoutKind.Sequential)] private struct BASIC {
        public long A; public long B; public uint LimitFlags; public UIntPtr C; public UIntPtr D;
        public uint E; public UIntPtr F; public uint G; public uint H;
    }
    [StructLayout(LayoutKind.Sequential)] private struct IO {
        public ulong A; public ulong B; public ulong C; public ulong D; public ulong E; public ulong F;
    }
    [StructLayout(LayoutKind.Sequential)] private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public BASIC BasicLimitInformation; public IO IoInfo; public UIntPtr A; public UIntPtr B; public UIntPtr C; public UIntPtr D;
    }
    [StructLayout(LayoutKind.Sequential)] private struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION {
        public long TotalUserTime; public long TotalKernelTime;
        public long ThisPeriodTotalUserTime; public long ThisPeriodTotalKernelTime;
        public uint TotalPageFaultCount; public uint TotalProcesses;
        public uint ActiveProcesses; public uint TotalTerminatedProcesses;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr CreateJobObject(IntPtr a, string n);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr OpenJobObject(uint a, bool i, string n);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool QueryInformationJobObject(IntPtr j, int c, IntPtr i, int l, out uint r);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool IsProcessInJob(IntPtr p, IntPtr j, out bool r);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool SetInformationJobObject(IntPtr j, int c, IntPtr i, uint l);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool CloseHandle(IntPtr h);
}
'@
}

function Get-VmbTransactionRecordPath {
    if ([string]::IsNullOrWhiteSpace([string]$env:APPDATA)) {
        throw 'APPDATA is unavailable; cannot establish the VMB machine transaction owner record.'
    }
    return Join-Path $env:APPDATA 'VMBLauncher\transaction_lease.json'
}

function Write-VmbTransactionRecordAtomic {
    param([string]$Path, [object]$Record)

    $directory = Split-Path -Parent $Path
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $backup = $Path + '.' + [guid]::NewGuid().ToString('N') + '.bak'
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    try {
        $json = $Record | ConvertTo-Json -Depth 8
        $bytes = $utf8NoBom.GetBytes($json)
        $stream = New-Object System.IO.FileStream(
            $temporary,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None,
            4096,
            [System.IO.FileOptions]::WriteThrough)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally { $stream.Dispose() }
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [System.IO.File]::Replace($temporary, $Path, $backup, $true)
            if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
        }
        else {
            [System.IO.File]::Move($temporary, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
    }
}

function Enter-VmbMachineTransactionLease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [string]$Mod,
        [string]$ProjectRoot,
        [ValidateRange(1, 3600000)][int]$TimeoutMilliseconds = 300000,
        [Alias('SemaphoreName')][string]$MutexName = $script:VmbTransactionMutexName,
        [string]$RecordPath = $(if ($env:VMBLAUNCHER_TRANSACTION_RECORD_PATH) { $env:VMBLAUNCHER_TRANSACTION_RECORD_PATH } else { Get-VmbTransactionRecordPath })
    )

    $processTreeJobName = [VmbTransactionProcessTreeGuard]::Ensure()

    # Nested same-process callers (ship -> publish-release) join the existing
    # lease before taking any subordinate lock. Validate the crash-safe record,
    # PID/start identity, and source root; environment text alone is not enough.
    $inheritedLeaseId = [Environment]::GetEnvironmentVariable($script:VmbTransactionLeaseIdEnvironmentVariable, 'Process')
    $inheritedOwnerPid = [Environment]::GetEnvironmentVariable($script:VmbTransactionOwnerPidEnvironmentVariable, 'Process')
    $inheritedOwnerStart = [Environment]::GetEnvironmentVariable($script:VmbTransactionOwnerStartEnvironmentVariable, 'Process')
    $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $currentStart = $currentProcess.StartTime.ToUniversalTime().Ticks
    if (-not [string]::IsNullOrWhiteSpace($inheritedLeaseId) -and
        "$inheritedOwnerPid" -eq "$PID" -and
        "$inheritedOwnerStart" -eq "$currentStart") {
        if (-not (Test-Path -LiteralPath $RecordPath -PathType Leaf)) {
            throw 'Refusing same-process transaction join: owner record is missing.'
        }
        try {
            $ownerRecord = [System.IO.File]::ReadAllText($RecordPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        }
        catch { throw "Refusing same-process transaction join: owner record is unreadable ($($_.Exception.Message))." }
        $requestedRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $null } else { [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]@('\', '/')) }
        $recordRoot = if ([string]::IsNullOrWhiteSpace([string]$ownerRecord.project_root)) { $null } else { [System.IO.Path]::GetFullPath([string]$ownerRecord.project_root).TrimEnd([char[]]@('\', '/')) }
        $modMismatch = -not [string]::IsNullOrWhiteSpace([string]$ownerRecord.mod) -and
            -not [string]::IsNullOrWhiteSpace($Mod) -and
            -not [string]::Equals([string]$ownerRecord.mod, $Mod, [System.StringComparison]::OrdinalIgnoreCase)
        if ("$($ownerRecord.schema)" -ne '2' -or
            "$($ownerRecord.process_tree_job_name)" -ne "$processTreeJobName" -or
            "$($ownerRecord.lease_id)" -ne "$inheritedLeaseId" -or
            "$($ownerRecord.owner_pid)" -ne "$PID" -or
            "$($ownerRecord.owner_start_utc_ticks)" -ne "$currentStart" -or
            $modMismatch -or
            -not [string]::Equals($requestedRoot, $recordRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing same-process transaction join: record identity or project root does not match.'
        }
        Write-Host ("[transaction-lease] joined owner_pid={0} session={1} action={2} owner_action={3} mod={4} root={5}" -f `
            $PID, $currentProcess.SessionId, $Action, $ownerRecord.action, `
            $(if ($ownerRecord.mod) { $ownerRecord.mod } else { '(none)' }), `
            $(if ($recordRoot) { $recordRoot } else { '(none)' })) -ForegroundColor DarkGray
        return [pscustomobject]@{
            MutexHolder = $null
            Acquired = $true
            OwnsMutex = $false
            LeaseId = $inheritedLeaseId
            OwnerPid = $PID
            OwnerStartUtcTicks = $currentStart
            SessionId = $currentProcess.SessionId
            Action = $Action
            Mod = $Mod
            ProjectRoot = $requestedRoot
            RecordPath = [System.IO.Path]::GetFullPath($RecordPath)
            PreviousEnvironment = $null
        }
    }

    $mutexHolder = $null
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        try {
            $mutexHolder = [VmbTransactionMutexHolder]::Acquire($MutexName, $TimeoutMilliseconds)
        }
        catch {
            $live = $null
            if (Test-Path -LiteralPath $RecordPath -PathType Leaf) {
                try { $live = [System.IO.File]::ReadAllText($RecordPath, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { }
            }
            $owner = if ($null -ne $live) {
                " owner_pid=$($live.owner_pid) session=$($live.session_id) action=$($live.action) mod=$($live.mod) root=$($live.project_root) acquired_utc=$($live.acquired_utc)."
            } else { '' }
            throw "Another VMB/Stingray transaction held the machine mutex for more than $TimeoutMilliseconds ms.$owner No mutation was started."
        }
        try {
            $priorExists = Test-Path -LiteralPath $RecordPath -PathType Leaf
            $stale = $null
            if ($priorExists) {
                $stale = [IO.File]::ReadAllText($RecordPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            }
            if ($null -eq $stale) {
                if ($priorExists -or $mutexHolder.WasAbandoned) {
                    throw 'prior ownership evidence exists but its durable owner record is missing or unreadable'
                }
            }
            else {
                if ("$($stale.schema)" -ne '2') { throw "prior owner record has unsupported schema $($stale.schema)" }
                $recordedOwnerLive = $false
                try {
                    $recordedProcess = [Diagnostics.Process]::GetProcessById([int]$stale.owner_pid)
                    try {
                        $recordedOwnerLive = -not $recordedProcess.HasExited -and
                            "$($recordedProcess.StartTime.ToUniversalTime().Ticks)" -eq "$($stale.owner_start_utc_ticks)"
                    }
                    finally { $recordedProcess.Dispose() }
                }
                catch [System.ArgumentException] { }
                if ($recordedOwnerLive) { throw "mutex was available while recorded owner PID $($stale.owner_pid) is still live" }
                if ([string]::IsNullOrWhiteSpace([string]$stale.process_tree_job_name) -or
                    -not ([string]$stale.process_tree_job_name).StartsWith('Global\Ensrick.VMBLauncher.Transaction.Process.', [StringComparison]::Ordinal)) {
                    throw 'prior owner record has no valid process-tree job identity'
                }
                [VmbTransactionProcessTreeGuard]::WaitForDrained([string]$stale.process_tree_job_name, $TimeoutMilliseconds)
            }
        }
        catch {
            # End the owner thread without ReleaseMutex and retain its kernel
            # handle. This protects both kernel-abandoned recovery and the
            # fresh-mutex-object case identified by a stale durable record.
            $recoveryKind = if ($mutexHolder.WasAbandoned) { 'abandoned' } else { 'prior' }
            $mutexHolder.Abandon()
            $mutexHolder = $null
            throw "Refusing $recoveryKind transaction recovery: $($_.Exception.Message)"
        }

        $process = [System.Diagnostics.Process]::GetCurrentProcess()
        $leaseId = [guid]::NewGuid().ToString('N')
        $startTicks = $process.StartTime.ToUniversalTime().Ticks
        $normalizedRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
            $null
        }
        else {
            [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]@('\', '/'))
        }
        $record = [ordered]@{
            schema = 2
            lease_id = $leaseId
            owner_pid = $PID
            owner_start_utc_ticks = $startTicks
            session_id = $process.SessionId
            action = $Action
            mod = $(if ([string]::IsNullOrWhiteSpace($Mod)) { $null } else { $Mod })
            project_root = $normalizedRoot
            acquired_utc = [DateTime]::UtcNow.ToString('o')
            process_tree_job_name = $processTreeJobName
        }
        Write-VmbTransactionRecordAtomic -Path $RecordPath -Record $record

        $previous = [ordered]@{
            lease_id = [Environment]::GetEnvironmentVariable($script:VmbTransactionLeaseIdEnvironmentVariable, 'Process')
            owner_pid = [Environment]::GetEnvironmentVariable($script:VmbTransactionOwnerPidEnvironmentVariable, 'Process')
            owner_start = [Environment]::GetEnvironmentVariable($script:VmbTransactionOwnerStartEnvironmentVariable, 'Process')
            record_path = [Environment]::GetEnvironmentVariable($script:VmbTransactionRecordPathEnvironmentVariable, 'Process')
        }
        [Environment]::SetEnvironmentVariable($script:VmbTransactionLeaseIdEnvironmentVariable, $leaseId, 'Process')
        [Environment]::SetEnvironmentVariable($script:VmbTransactionOwnerPidEnvironmentVariable, "$PID", 'Process')
        [Environment]::SetEnvironmentVariable($script:VmbTransactionOwnerStartEnvironmentVariable, "$startTicks", 'Process')
        [Environment]::SetEnvironmentVariable($script:VmbTransactionRecordPathEnvironmentVariable, [System.IO.Path]::GetFullPath($RecordPath), 'Process')

        Write-Host ("[transaction-lease] acquired owner_pid={0} session={1} action={2} mod={3} root={4} wait_ms={5}" -f `
            $PID, $process.SessionId, $Action, $(if ($Mod) { $Mod } else { '(none)' }), `
            $(if ($normalizedRoot) { $normalizedRoot } else { '(none)' }), $watch.ElapsedMilliseconds) -ForegroundColor DarkGray

        return [pscustomobject]@{
            MutexHolder = $mutexHolder
            Acquired = $true
            OwnsMutex = $true
            LeaseId = $leaseId
            OwnerPid = $PID
            OwnerStartUtcTicks = $startTicks
            SessionId = $process.SessionId
            Action = $Action
            Mod = $Mod
            ProjectRoot = $normalizedRoot
            RecordPath = [System.IO.Path]::GetFullPath($RecordPath)
            PreviousEnvironment = $previous
        }
    }
    catch {
        if ($null -ne $mutexHolder) { $mutexHolder.Dispose() }
        throw
    }
}

function Exit-VmbMachineTransactionLease {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Lease)

    if (-not $Lease.Acquired) { return }
    if (-not $Lease.OwnsMutex) {
        $Lease.Acquired = $false
        Write-Host ("[transaction-lease] left joined scope owner_pid={0} session={1} action={2} mod={3} root={4}" -f `
            $Lease.OwnerPid, $Lease.SessionId, $Lease.Action, $(if ($Lease.Mod) { $Lease.Mod } else { '(none)' }), `
            $(if ($Lease.ProjectRoot) { $Lease.ProjectRoot } else { '(none)' })) -ForegroundColor DarkGray
        return
    }
    $releaseFailure = $null
    $mutexReleased = $false
    try {
        try {
            [VmbTransactionProcessTreeGuard]::TerminateAndWaitForResidualDescendants(10000)
            if (-not (Test-Path -LiteralPath $Lease.RecordPath -PathType Leaf)) {
                throw 'transaction owner record disappeared before mutex release'
            }
            $recordText = [System.IO.File]::ReadAllText($Lease.RecordPath, [System.Text.Encoding]::UTF8)
            $record = $recordText | ConvertFrom-Json
            if ("$($record.lease_id)" -ne "$($Lease.LeaseId)") {
                throw 'transaction owner record identity changed before mutex release'
            }
            Remove-Item -LiteralPath $Lease.RecordPath -Force
            if (Test-Path -LiteralPath $Lease.RecordPath) {
                throw 'transaction owner record still exists after authenticated deletion'
            }
            $Lease.MutexHolder.Dispose()
            $mutexReleased = $true
        }
        catch {
            $releaseFailure = "could not authenticate cleanup/release mutex: $($_.Exception.Message)"
            if (-not $mutexReleased) {
                try { $Lease.MutexHolder.Abandon() }
                catch { $releaseFailure += "; could not re-abandon mutex: $($_.Exception.Message)" }
            }
        }
    }
    finally {
        foreach ($restore in @(
            @($script:VmbTransactionLeaseIdEnvironmentVariable, $Lease.PreviousEnvironment.lease_id),
            @($script:VmbTransactionOwnerPidEnvironmentVariable, $Lease.PreviousEnvironment.owner_pid),
            @($script:VmbTransactionOwnerStartEnvironmentVariable, $Lease.PreviousEnvironment.owner_start),
            @($script:VmbTransactionRecordPathEnvironmentVariable, $Lease.PreviousEnvironment.record_path)
        )) {
            if ($null -eq $restore[1]) { Remove-Item -LiteralPath ("Env:" + $restore[0]) -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable([string]$restore[0], [string]$restore[1], 'Process') }
        }
        $Lease.Acquired = $false
    }
    if ($releaseFailure) {
        $state = if ($mutexReleased) { 'mutex released after authenticated cleanup' } else { 'mutex re-abandoned; mutation remains fail-closed' }
        Write-Host "[transaction-lease] CRITICAL $state owner_pid=$($Lease.OwnerPid) action=$($Lease.Action): $releaseFailure" -ForegroundColor Red
        throw "CRITICAL: $releaseFailure"
    }
    Write-Host ("[transaction-lease] released owner_pid={0} session={1} action={2} mod={3} root={4}" -f `
        $Lease.OwnerPid, $Lease.SessionId, $Lease.Action, $(if ($Lease.Mod) { $Lease.Mod } else { '(none)' }), `
        $(if ($Lease.ProjectRoot) { $Lease.ProjectRoot } else { '(none)' })) -ForegroundColor DarkGray
}
