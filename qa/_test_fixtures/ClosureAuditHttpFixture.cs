// Private deterministic transport fixture. Never loaded by production.
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;

namespace Vt2.GitHub.Qa
{
    public sealed class Plan
    {
        public byte[] Body = new byte[0];
        public int Status = 200;
        public string ContentType = "application/json; charset=utf-8";
        public string ContentEncoding;
        public long? DeclaredLength;
        public int HeaderDelay, StreamDelay, ReadDelay, ChunkSize = 8192;
        public bool IgnoreCancellation, HeaderThrows, ReadThrows;
        public string ErrorText = "private fixture exception";
        public int Reads, BytesRead, SerializeCalls, StreamDisposals, ContentDisposals, ResponseDisposals;
        public readonly TaskCompletionSource<bool> HeaderFinished = new TaskCompletionSource<bool>();
    }

    public sealed class RequestRecord
    {
        public string Method, Uri, Body, Authorization;
        public HttpRequestMessage Request;
    }

    public sealed class Handler : HttpMessageHandler
    {
        public readonly Queue<Plan> Plans = new Queue<Plan>();
        public readonly List<RequestRecord> Requests = new List<RequestRecord>();
        public bool Disposed;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests.Add(new RequestRecord {
                Method = request.Method.Method, Uri = request.RequestUri.AbsoluteUri,
                Body = await request.Content.ReadAsStringAsync().ConfigureAwait(false),
                Authorization = request.Headers.Authorization == null ? null : request.Headers.Authorization.ToString(),
                Request = request
            });
            if (Plans.Count == 0) throw new InvalidOperationException("fixture exhausted; no real network exists");
            Plan plan = Plans.Dequeue();
            try
            {
                if (plan.HeaderDelay > 0)
                    await Task.Delay(plan.HeaderDelay, plan.IgnoreCancellation ? CancellationToken.None : token).ConfigureAwait(false);
                if (plan.HeaderThrows) throw new InvalidOperationException(plan.ErrorText);
                return new Response(plan);
            }
            finally { plan.HeaderFinished.TrySetResult(true); }
        }
        protected override void Dispose(bool disposing) { Disposed = true; base.Dispose(disposing); }
    }

    internal sealed class Response : HttpResponseMessage
    {
        private readonly Plan plan;
        private bool disposed;
        public Response(Plan plan) : base((HttpStatusCode)plan.Status)
        {
            this.plan = plan;
            Content = new Content(plan);
            if (plan.Status >= 300 && plan.Status < 400) Headers.Location = new Uri("https://fixture.invalid/never-follow");
        }
        protected override void Dispose(bool disposing)
        {
            if (!disposed) { disposed = true; Interlocked.Increment(ref plan.ResponseDisposals); }
            base.Dispose(disposing);
        }
    }

    internal sealed class Content : HttpContent
    {
        private readonly Plan plan;
        private readonly BodyStream stream;
        private bool disposed;
        public Content(Plan plan)
        {
            this.plan = plan; stream = new BodyStream(plan);
            if (!String.IsNullOrEmpty(plan.ContentType)) Headers.ContentType = MediaTypeHeaderValue.Parse(plan.ContentType);
            if (plan.ContentEncoding != null) Headers.ContentEncoding.Add(plan.ContentEncoding);
        }
        protected override bool TryComputeLength(out long length)
        {
            length = plan.DeclaredLength ?? 0;
            return plan.DeclaredLength.HasValue;
        }
        protected override async Task<Stream> CreateContentReadStreamAsync()
        {
            if (plan.StreamDelay > 0) await Task.Delay(plan.StreamDelay).ConfigureAwait(false);
            return stream;
        }
        protected override Task SerializeToStreamAsync(Stream destination, TransportContext context)
        {
            Interlocked.Increment(ref plan.SerializeCalls);
            return stream.CopyToAsync(destination);
        }
        protected override void Dispose(bool disposing)
        {
            if (!disposed) { disposed = true; Interlocked.Increment(ref plan.ContentDisposals); }
            stream.Dispose();
            base.Dispose(disposing);
        }
    }

    internal sealed class BodyStream : Stream
    {
        private readonly Plan plan;
        private int position;
        private bool disposed;
        public BodyStream(Plan plan) { this.plan = plan; }
        public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken token)
        {
            Interlocked.Increment(ref plan.Reads);
            if (plan.ReadDelay > 0)
                await Task.Delay(plan.ReadDelay, plan.IgnoreCancellation ? CancellationToken.None : token).ConfigureAwait(false);
            if (plan.ReadThrows) throw new InvalidOperationException(plan.ErrorText);
            if (disposed) throw new ObjectDisposedException("fixture stream");
            int result = Math.Min(Math.Min(count, plan.ChunkSize), plan.Body.Length - position);
            Array.Copy(plan.Body, position, buffer, offset, result);
            position += result; Interlocked.Add(ref plan.BytesRead, result);
            return result;
        }
        protected override void Dispose(bool disposing)
        {
            if (!disposed) { disposed = true; Interlocked.Increment(ref plan.StreamDisposals); }
            base.Dispose(disposing);
        }
        public override bool CanRead { get { return true; } }
        public override bool CanSeek { get { return false; } }
        public override bool CanWrite { get { return false; } }
        public override long Length { get { throw new NotSupportedException(); } }
        public override long Position { get { return position; } set { throw new NotSupportedException(); } }
        public override int Read(byte[] buffer, int offset, int count) { throw new InvalidOperationException("synchronous read forbidden"); }
        public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
        public override void SetLength(long length) { throw new NotSupportedException(); }
        public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
        public override void Flush() { }
    }
}
