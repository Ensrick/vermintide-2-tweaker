// #1527: one fixed read-only GraphQL operation, never a general HTTP client.
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace Vt2.GitHub
{
    public sealed class ClosureAuditTransport : IDisposable
    {
        private const string Endpoint = "https://api.github.com/graphql";
        // Collector-owned query, LF-normalized only for cross-checkout identity.
        private const string QueryHash = "aee04978ed058bf0dedff917a838f91a80aa75fe8dd3379ebf1866a594a5ae07";
        private readonly HttpClient client;
        private readonly CancellationTokenSource cancellation;
        private readonly Stopwatch timer = Stopwatch.StartNew();
        private readonly SecureString token;
        private readonly string query, owner, repository;
        private readonly int issue, deadline, responseLimit, totalLimit, requestLimit;
        public int RequestCount { get; private set; }
        public long ResponseBytes { get; private set; }
        public string FailureCode { get; private set; }
        public bool Disposed { get; private set; }
        public long ElapsedMilliseconds { get { return timer.ElapsedMilliseconds; } }
        public bool DeadlineExceeded { get { return timer.ElapsedMilliseconds >= deadline; } }

        public ClosureAuditTransport(SecureString token, string query, string owner, string repository,
            int issue, int deadline, int responseLimit, int totalLimit, int requestLimit)
            : this(token, query, owner, repository, issue, deadline, responseLimit, totalLimit,
                requestLimit, NewHandler()) { }

        // QA uses reflection to inject a private in-memory handler. There is no
        // endpoint/handler/factory parameter in the exported PowerShell API.
        private ClosureAuditTransport(SecureString token, string query, string owner, string repository,
            int issue, int deadline, int responseLimit, int totalLimit, int requestLimit,
            HttpMessageHandler handler)
        {
            try
            {
                if (token == null || token.Length == 0 || token.Length > 4096 || issue <= 0 ||
                    deadline < 1 || deadline > 60000 || responseLimit < 1 || responseLimit > 16777216 ||
                    totalLimit < 1 || totalLimit > 67108864 || requestLimit < 1 || requestLimit > 44 ||
                    !ScopePart(owner) || !ScopePart(repository) || handler == null || query == null)
                    throw new InvalidOperationException();
                using (SHA256 hash = SHA256.Create())
                {
                    string actual = BitConverter.ToString(hash.ComputeHash(
                        new UTF8Encoding(false, true).GetBytes(query.Replace("\r\n", "\n"))))
                        .Replace("-", "").ToLowerInvariant();
                    if (actual != QueryHash) throw new InvalidOperationException();
                }
                this.token = token.Copy();
                this.token.MakeReadOnly();
                this.query = query; this.owner = owner; this.repository = repository; this.issue = issue;
                this.deadline = deadline; this.responseLimit = responseLimit;
                this.totalLimit = totalLimit; this.requestLimit = requestLimit;
                client = new HttpClient(handler, true);
                client.Timeout = Timeout.InfiniteTimeSpan;
                cancellation = new CancellationTokenSource();
                cancellation.CancelAfter(deadline);
            }
            catch
            {
                if (this.token != null) this.token.Dispose();
                if (client != null) client.Dispose(); else if (handler != null) handler.Dispose();
                if (cancellation != null) cancellation.Dispose();
                throw new InvalidOperationException("closure-transport:configuration");
            }
        }

        private static HttpClientHandler NewHandler()
        {
            return new HttpClientHandler {
                AllowAutoRedirect = false, UseCookies = false, UseDefaultCredentials = false,
                AutomaticDecompression = DecompressionMethods.None, MaxResponseHeadersLength = 32
            };
        }

        private static bool ScopePart(string value)
        {
            if (String.IsNullOrEmpty(value) || value.Length > 100) return false;
            foreach (char c in value)
                if (!(c >= 'a' && c <= 'z') && !(c >= 'A' && c <= 'Z') &&
                    !(c >= '0' && c <= '9') && c != '-' && c != '_' && c != '.') return false;
            return true;
        }

        private void CheckDeadline()
        {
            if (Disposed || FailureCode != null) throw new InvalidOperationException("closed");
            if (timer.ElapsedMilliseconds >= deadline || cancellation.IsCancellationRequested)
                throw new OperationCanceledException();
        }

        // Race every asynchronous boundary against the SAME total cancellation.
        // A late successful header/stream task is disposed even if a handler
        // ignores cancellation. Production HttpClientHandler is also disposed.
        private async Task<T> Bounded<T>(Task<T> task, Action<T> disposeLate)
        {
            var cancelled = new TaskCompletionSource<bool>();
            using (cancellation.Token.Register(() => cancelled.TrySetResult(true)))
            {
                if (await Task.WhenAny(task, cancelled.Task).ConfigureAwait(false) != task)
                {
                    ObserveLate(task, disposeLate);
                    throw new OperationCanceledException();
                }
                return await task.ConfigureAwait(false);
            }
        }

        private static void ObserveLate<T>(Task<T> task, Action<T> disposeLate)
        {
            task.ContinueWith(t => {
                try {
                    if (t.Status == TaskStatus.RanToCompletion && disposeLate != null) disposeLate(t.Result);
                    else if (t.IsFaulted) { var observed = t.Exception; }
                } catch { /* cleanup must never leak an untrusted exception */ }
            }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        }

        private static string Quote(string value)
        {
            if (value == null) return "null";
            var text = new StringBuilder("\"");
            foreach (char c in value)
            {
                if (c == '"' || c == '\\') text.Append('\\').Append(c);
                else if (c < 32) text.Append("\\u").Append(((int)c).ToString("x4"));
                else text.Append(c);
            }
            return text.Append('"').ToString();
        }

        public string ReadPage(object cursor)
        {
            try {
                if (cursor != null && !(cursor is string)) throw new InvalidDataException("cursor");
                return ReadPageAsync((string)cursor).GetAwaiter().GetResult();
            }
            catch (OperationCanceledException) { FailureCode = "deadline"; }
            catch (DecoderFallbackException) { FailureCode = "utf8"; }
            catch (Exception ex)
            {
                // Only our closed vocabulary crosses the PowerShell boundary.
                string code = ex is InvalidDataException ? ex.Message : "io";
                switch (code)
                {
                    case "request-bound": case "request-byte-bound": case "response-byte-bound": case "total-byte-bound":
                    case "authentication": case "redirect": case "http-status":
                    case "content-type": case "content-encoding": case "json-wire":
                    case "cursor": FailureCode = code; break;
                    default: FailureCode = "io"; break;
                }
            }
            throw new InvalidOperationException("closure-transport:" + FailureCode);
        }

        private async Task<string> ReadPageAsync(string after)
        {
            CheckDeadline();
            if (RequestCount >= requestLimit) throw new InvalidDataException("request-bound");
            if (ResponseBytes >= totalLimit) throw new InvalidDataException("total-byte-bound");
            if (after != null && (after.Length == 0 || after.Length > 512)) throw new InvalidDataException("cursor");
            string body = "{\"query\":" + Quote(query) + ",\"variables\":{\"owner\":" + Quote(owner) +
                ",\"name\":" + Quote(repository) + ",\"number\":" + issue.ToString(System.Globalization.CultureInfo.InvariantCulture) +
                ",\"after\":" + Quote(after) + "}}";
            var utf8 = new UTF8Encoding(false, true);
            byte[] requestBytes = utf8.GetBytes(body);
            if (requestBytes.Length > 8192) throw new InvalidDataException("request-byte-bound");
            using (var request = new HttpRequestMessage(HttpMethod.Post, Endpoint))
            {
                request.Headers.UserAgent.ParseAdd("vt2-public-release-closure-audit/1.0");
                request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
                request.Headers.Add("X-GitHub-Api-Version", "2022-11-28");
                request.Content = new ByteArrayContent(requestBytes);
                request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json") { CharSet = "utf-8" };
                IntPtr secret = IntPtr.Zero;
                try
                {
                    secret = Marshal.SecureStringToBSTR(token);
                    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Marshal.PtrToStringBSTR(secret));
                }
                finally { if (secret != IntPtr.Zero) Marshal.ZeroFreeBSTR(secret); }
                RequestCount++;
                try
                {
                    using (HttpResponseMessage response = await Bounded(
                        client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellation.Token),
                        r => r.Dispose()).ConfigureAwait(false))
                    {
                        CheckDeadline();
                        int status = (int)response.StatusCode;
                        if (status >= 300 && status < 400) throw new InvalidDataException("redirect");
                        if (status == 401 || status == 403) throw new InvalidDataException("authentication");
                        if (status != 200) throw new InvalidDataException("http-status");
                        if (response.Content == null) throw new InvalidDataException("content-type");
                        var headers = response.Content.Headers;
                        var type = headers.ContentType;
                        if (type == null || !String.Equals(type.MediaType, "application/json", StringComparison.OrdinalIgnoreCase) ||
                            (!String.IsNullOrEmpty(type.CharSet) && !String.Equals(type.CharSet.Trim('"'), "utf-8", StringComparison.OrdinalIgnoreCase)))
                            throw new InvalidDataException("content-type");
                        if (headers.ContentEncoding.Count != 0) throw new InvalidDataException("content-encoding");
                        if (headers.ContentLength.HasValue && headers.ContentLength.Value > responseLimit)
                            throw new InvalidDataException("response-byte-bound");
                        if (headers.ContentLength.HasValue && headers.ContentLength.Value > totalLimit - ResponseBytes)
                            throw new InvalidDataException("total-byte-bound");
                        using (Stream stream = await Bounded(response.Content.ReadAsStreamAsync(), s => s.Dispose()).ConfigureAwait(false))
                        using (var bytes = new MemoryStream())
                        {
                            byte[] buffer = new byte[8192];
                            while (true)
                            {
                                CheckDeadline();
                                // At most ONE excess byte is read to prove oversize;
                                // neither a missing nor a lying Content-Length is trusted.
                                long remaining = Math.Min(responseLimit - bytes.Length, totalLimit - ResponseBytes);
                                int wanted = (int)Math.Min(buffer.Length, remaining + 1);
                                int count = await Bounded(stream.ReadAsync(buffer, 0, wanted, cancellation.Token), (Action<int>)null).ConfigureAwait(false);
                                ResponseBytes += count;
                                CheckDeadline();
                                if (count > responseLimit - bytes.Length) throw new InvalidDataException("response-byte-bound");
                                if (ResponseBytes > totalLimit) throw new InvalidDataException("total-byte-bound");
                                if (count == 0) break;
                                bytes.Write(buffer, 0, count);
                            }
                            string text = utf8.GetString(bytes.ToArray());
                            ValidateJsonWire(text);
                            CheckDeadline();
                            return text;
                        }
                    }
                }
                finally { request.Headers.Authorization = null; }
            }
        }

        // A bounded lexical preflight, NOT a replacement JSON parser. Both PS5
        // and PS7 silently replace escaped lone surrogates during JSON parsing.
        // Reject them before ConvertFrom-Json; cap depth/tokens and reject the
        // comment/trailing-comma/non-JSON-scalar extensions accepted by the
        // supported hosts. Host ConvertFrom-Json still owns structural parsing.
        private void ValidateJsonWire(string text)
        {
            int depth = 0, tokens = 0;
            char previous = '\0';
            string trimmed = text.Trim(' ', '\t', '\r', '\n');
            if (!trimmed.StartsWith("{", StringComparison.Ordinal) || !trimmed.EndsWith("}", StringComparison.Ordinal))
                throw new InvalidDataException("json-wire");
            for (int i = 0; i < text.Length; i++)
            {
                if ((i & 1023) == 0) CheckDeadline();
                char c = text[i];
                if (" \t\r\n".IndexOf(c) >= 0) continue;
                if (c == '"')
                {
                    bool closed = false;
                    while (++i < text.Length)
                    {
                        if ((i & 1023) == 0) CheckDeadline();
                        c = text[i];
                        if (c == '"') { closed = true; break; }
                        if (c < 32) throw new InvalidDataException("json-wire");
                        if (c != '\\') continue;
                        if (++i >= text.Length) throw new InvalidDataException("json-wire");
                        c = text[i];
                        if (c == 'u')
                        {
                            int point = Hex4(text, ref i);
                            if (point >= 0xdc00 && point <= 0xdfff) throw new InvalidDataException("json-wire");
                            if (point >= 0xd800 && point <= 0xdbff)
                            {
                                if (i + 2 >= text.Length || text[++i] != '\\' || text[++i] != 'u') throw new InvalidDataException("json-wire");
                                int low = Hex4(text, ref i);
                                if (low < 0xdc00 || low > 0xdfff) throw new InvalidDataException("json-wire");
                            }
                        }
                        else if ("\"\\/bfnrt".IndexOf(c) < 0) throw new InvalidDataException("json-wire");
                    }
                    if (!closed) throw new InvalidDataException("json-wire");
                    previous = '"';
                }
                else
                {
                    if (c == '/' || c == '\'') throw new InvalidDataException("json-wire");
                    if (c == '{' || c == '[') { if (++depth > 32) throw new InvalidDataException("json-wire"); tokens++; }
                    if (c == '}' || c == ']') { if (--depth < 0) throw new InvalidDataException("json-wire"); }
                    if (c == ':' && previous != '"') throw new InvalidDataException("json-wire");
                    if (c == ':' || c == ',') tokens++;
                    if (tokens > 131072) throw new InvalidDataException("json-wire");
                    if (c == ',')
                    {
                        if (previous == '[' || previous == ',') throw new InvalidDataException("json-wire");
                        int next = i + 1;
                        while (next < text.Length && " \t\r\n".IndexOf(text[next]) >= 0) next++;
                        if (next < text.Length && (text[next] == '}' || text[next] == ']')) throw new InvalidDataException("json-wire");
                    }
                    else if (" \t\r\n:{}[]".IndexOf(c) < 0)
                    {
                        int start = i;
                        while (i + 1 < text.Length && " \t\r\n:{}[],\"".IndexOf(text[i + 1]) < 0)
                        {
                            if (i - start >= 63) throw new InvalidDataException("json-wire");
                            i++;
                        }
                        string scalar = text.Substring(start, i - start + 1);
                        if (scalar != "null" && scalar != "true" && scalar != "false" &&
                            !Regex.IsMatch(scalar, @"\A-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\z", RegexOptions.CultureInvariant))
                            throw new InvalidDataException("json-wire");
                        if (++tokens > 131072) throw new InvalidDataException("json-wire");
                        c = 'v';
                    }
                    previous = c;
                }
            }
            if (depth != 0) throw new InvalidDataException("json-wire");
        }

        private static int Hex4(string text, ref int index)
        {
            int result = 0;
            for (int n = 0; n < 4; n++)
            {
                if (++index >= text.Length) throw new InvalidDataException("json-wire");
                char c = text[index];
                int digit = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
                if (digit < 0) throw new InvalidDataException("json-wire");
                result = result * 16 + digit;
            }
            return result;
        }

        public void Dispose()
        {
            if (Disposed) return;
            Disposed = true;
            try { cancellation.Cancel(); } catch { }
            try { client.Dispose(); } catch { }
            try { token.Dispose(); } catch { }
            try { cancellation.Dispose(); } catch { }
            timer.Stop();
        }
    }
}
