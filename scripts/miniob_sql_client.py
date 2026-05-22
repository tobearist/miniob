#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""向 MiniOB observer 发送单条 SQL 并读取结果（与 miniob_test.py 协议一致）。"""

import argparse
import select
import socket
import sys
import time


def run_sql_unix(sock_path: str, sql: str, timeout: int = 15) -> str:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    s.setblocking(False)
    poller = select.poll()
    poller.register(s, select.POLLIN | select.POLLHUP | select.POLLERR)

    payload = sql.encode("utf-8") + b"\0"
    s.sendall(payload)

    result = ""
    deadline = time.time() + timeout
    while time.time() < deadline:
        events = poller.poll(500)
        if not events:
            continue
        _, event = events[0]
        if event & (select.POLLHUP | select.POLLERR):
            break
        data = s.recv(8192)
        if len(data) == 0:
            break
        chunk = data.decode("utf-8", errors="replace")
        if data[-1] == 0:
            result += chunk[:-1]
            break
        result += chunk

    s.close()
    return result.strip()


def run_sql_tcp(port: int, sql: str, timeout: int = 15) -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(("127.0.0.1", port))
    s.setblocking(False)
    poller = select.poll()
    poller.register(s, select.POLLIN | select.POLLHUP | select.POLLERR)

    payload = sql.encode("utf-8") + b"\0"
    s.sendall(payload)

    result = ""
    deadline = time.time() + timeout
    while time.time() < deadline:
        events = poller.poll(500)
        if not events:
            continue
        _, event = events[0]
        if event & (select.POLLHUP | select.POLLERR):
            break
        data = s.recv(8192)
        if len(data) == 0:
            break
        chunk = data.decode("utf-8", errors="replace")
        if data[-1] == 0:
            result += chunk[:-1]
            break
        result += chunk

    s.close()
    return result.strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("-s", "--socket", default="", help="unix socket path")
    parser.add_argument("-p", "--port", type=int, default=0, help="tcp port")
    parser.add_argument("-t", "--timeout", type=int, default=15)
    parser.add_argument("sql", help="sql to execute")
    args = parser.parse_args()

    try:
        if args.socket:
            out = run_sql_unix(args.socket, args.sql, args.timeout)
        elif args.port > 0:
            out = run_sql_tcp(args.port, args.sql, args.timeout)
        else:
            print("need -s socket or -p port", file=sys.stderr)
            return 2
        print(out)
        return 0
    except Exception as ex:
        print(str(ex), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
