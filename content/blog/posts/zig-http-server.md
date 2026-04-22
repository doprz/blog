---
date: '2026-04-21'
draft: false
title: 'Writing a Simple yet Performant HTTP/1.1 Server in Zig 0.16'
---
If you've written network code in earlier versions of Zig or in C, then the patterns here will feel familiar. This post walks through building a minimal HTTP/1.1 server using nothing but the Zig standard library.

The full source code for this blog post is available as a self-contained `main.zig` and `main-async.zig` with no external dependencies other than the Zig 0.16 standard library on [GitHub](https://github.com/doprz/zig-http-server).

## A Brief History of I/O In Zig

**Zig 0.15.1** - "Writergate": All existing `std.io` readers and writers were deprecated in favor of the new `std.Io.Reader` and `std.Io.Writer`. These are non-generic structs that hold both a vtable pointer and buffer. The buffer lives in the interface and not in the implementation.

References:
- https://ziglang.org/download/0.15.1/release-notes.html#Writergate

**Zig 0.16** - `Io` Instance and "Juicy Main": All input and output functionality requires being passed in an `Io` instance. In addition to this, the classic `pub fn main() !void` signature is replaced by adding a new parameter to main: `std.process.Init` or also known as "Juicy Main".

References:
- https://ziglang.org/download/0.16.0/release-notes.html#IO-as-an-Interface
- https://ziglang.org/download/0.16.0/release-notes.html#Juicy-Main

## The Two-Layer Model

One thing that trips up newcomers is that there are two distinct "servers" in the code, however, they operate at different levels of the network stack and it's worth keeping this in mind moving forward.

- **The TCP Server** (`std.Io.net`) - binds a port, accepts connections, and gives you a raw byte stream.
- **The HTTP Server** (`std.http.Server`) - sits on top of that stream and parses it as HTTP/1.1.

## Code Explained

```zig
const std = @import("std");
const log = std.log.scoped(.server);

const LISTEN_ADDR = "127.0.0.1";
const LISTEN_PORT = 8000;

fn startServer(io: std.Io) !void {
    log.info("Listening on http://{s}:{d}", .{ LISTEN_ADDR, LISTEN_PORT });
    const addr = std.Io.net.IpAddress.parseIp4(LISTEN_ADDR, LISTEN_PORT) catch unreachable;

    // TCP layer: bind the port and accept the raw streams
    var server = try addr.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    while (true) {
        log.info("Waiting for connection...", .{});
        var stream = try server.accept(io);
        defer stream.close(io);
        log.info("TCP connection established", .{});

        // Wrap the raw stream in buffered Io.Reader / Io.Writer
        var read_buffer: [1024]u8 = undefined;
        var write_buffer: [1024]u8 = undefined;
        var reader = stream.reader(io, &read_buffer);
        var writer = stream.writer(io, &write_buffer);

        // HTTP layer: parse the byte stream at HTTP/1.1
        var http_server = std.http.Server.init(&reader.interface, &writer.interface);
        var req = try http_server.receiveHead();
        log.info("{s} {s}", .{ @tagName(req.head.method), req.head.target });

        try req.respond("Hello World!", .{ .status = .ok });
        log.info("Response sent, closing connection", .{});
    }
}

pub fn main(init: std.process.Init) !void {
    log.info("Starting server", .{});
    try startServer(init.io);
}
```

## Concurrency and Performance

This server currently can only handle one connection at a time. If we want multiple connections and better performance we can do 4 things:

- `std.Io.Group` - Each accepted connection is handed off to `handleStream` as it's own async task. This lets the server accept new connections while existing ones are still being served.
    ```zig
        var group: std.Io.Group = .init;
        defer group.cancel(io);
    
        while (true) {
            const stream = try server.accept(io);
            group.async(io, handleStream, .{ io, stream });
        }
    
        try group.await(io);
    ```
- Keep-alive connections - The inner `while (true)` loop in `handleStream` is the single biggest performance lever. Without it, every request pays the full cost of a TCP handshake. With it, `wrk` and real browsers can reuse the same connection for many requests. Running `wrk` at this stage results in a bunch of `error.HttpConnectionClosign` errors but we can handle it silently by just returning.
  ```zig
    while (true) {
        var req = http_server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => return,
        };

        req.respond("Hello World!", .{ .status = .ok }) catch |err| {
            log.err("failed to respond: {}", .{err});
        };
    }
  ```
- Buffer size - Read and write buffers are now set to 4096 bytes. The original 1024-byte buffers are small enough that a request with typical headers can require multiple reads to assemble. 4096 covers the vast majority of real-world requests in a single. Increasing the buffers to 8192 bytes shows minimal performance increases in benchmarks.
- No per-request logging: Logging every request through `log.info` is a significant bottleneck under load. Removing it from the hot path while keeping error logging was one of the more impactful changes for performance. If you need per-request logging in a production environment, we would batch log writes.

# Benchmark

Command: `wrk -t4 -c100 -d10s <url>`
- 4 Threads
- 100 Connections
- 10s Duration

```sh
  4 threads and 100 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency    24.41us   12.36us   3.03ms   77.19%
    Req/Sec   150.24k     4.42k  163.87k    71.29%
  4528369 requests in 10.10s, 220.25MB read
Requests/sec: 448351.64
Transfer/sec:     21.81MB
```

For comparison, Caddy serving `caddy respond "Hello World!"`:
```sh
  4 threads and 100 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency   210.64us  235.88us   5.07ms   86.67%
    Req/Sec   111.41k     1.73k  115.95k    75.50%
  4478865 requests in 10.10s, 615.08MB read
Requests/sec: 443457.86
Transfer/sec:     60.90MB
```

~448k vs ~443k req/s is essentially identical. This is ~50 lines of straightforward Zig standard library code matching a production-hardended server.

That said, this benchmark is about as favorable as it gets for a minimal server. A static "Hello World!" response with no routing, no middleware, and no "real" work to do is precisely the scenario where simplicity wins. In any benchmark that resembles real-world usage such as TLS termination, dynamic routing, HTTP/2, or serving static files - Caddy would pull ahead and by a lot. Matching its throughput on a toy benchmark is a fun result, but it says more about how well Zig's standard library is designed than it does about production readiness. If you're building something real, use the right tool for the job and Caddy is absolutely that for many use cases.

## Why Zig

50 lines where you fully understand every allocation and what every line does is a valuable piece of code. It may not match or replace Caddy or other production-ready software but it's about building something that you understand from start to finish and you can build upon; be it a reverse-proxy, a load-balancer, or something else.
