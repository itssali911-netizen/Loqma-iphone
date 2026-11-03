"""Local read-only catalogue API; expose publicly only behind a managed HTTPS proxy.

No user data, no writable endpoint, no credentials. A read-only connection is
opened per request. Query work has a deadline; the connection pool is bounded.
Full export is opt-in and needs separate proxy bandwidth/rate controls.
"""
import argparse
import gzip
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading
import time
from urllib.parse import parse_qs, unquote, urlparse
import zlib

from catalog import LICENCE, canonical, connect, lookup, search


def create_server(database, host="127.0.0.1", port=8781, allow_export=False):
    path = Path(database).resolve()
    if not path.is_file():
        raise ValueError("Import a catalogue database first")
    slots = threading.BoundedSemaphore(8)

    class Handler(BaseHTTPRequestHandler):
        # HTTP/1.0 closes streaming responses at EOF; no invalid chunk framing.
        protocol_version = "HTTP/1.0"
        server_version = "LuqmaOFFCatalog/1"

        def setup(self):
            super().setup()
            self.connection.settimeout(30)

        def log_message(self, *_):
            # Query strings can contain private diet information. Do not log.
            pass

        def respond(self, status, payload):
            body = canonical(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "private, max-age=60" if status == 200 else "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if len(self.path) > 2048:
                self.respond(414, {"error": "request-too-long"})
                return
            if not slots.acquire(blocking=False):
                self.respond(503, {"error": "catalogue-busy"})
                return
            db = None
            try:
                db = connect(path, readonly=True)
                deadline = time.monotonic() + 8
                db.set_progress_handler(lambda: int(time.monotonic() > deadline), 10000)
                route = urlparse(self.path)
                query = parse_qs(route.query, max_num_fields=8)
                if route.path == "/v1/products":
                    payload = search(db, query.get("q", [""])[0], int(query.get("page", ["1"])[0]),
                                     int(query.get("page_size", ["50"])[0]))
                elif route.path.startswith("/v1/products/"):
                    payload = lookup(db, unquote(route.path[len("/v1/products/"):]))
                elif route.path == "/v1/licence":
                    payload = {"licence": LICENCE, "database_export": "/v1/export" if allow_export else None,
                               "scope": "Public Open Food Facts catalogue only; no personal Luqma data"}
                elif route.path == "/v1/status":
                    states = [dict(row) for row in db.execute("SELECT * FROM imports ORDER BY started_at DESC LIMIT 3")]
                    payload = {"format": "luqma-off-catalog", "version": 1, "imports": states}
                elif route.path == "/v1/export" and allow_export:
                    # Offer the actually used derivative data, not an unrelated
                    # upstream download. Public fields only, streamed boundedly.
                    db.set_progress_handler(None, 0)
                    self.send_response(200)
                    self.send_header("Content-Type", "application/gzip")
                    self.send_header("Content-Disposition", 'attachment; filename="luqma-off-derived.jsonl.gz"')
                    self.send_header("Cache-Control", "no-store")
                    self.end_headers()
                    with gzip.GzipFile(fileobj=self.wfile, mode="wb", mtime=0) as stream:
                        for row in db.execute("SELECT code,raw_zlib,food_json,export_id FROM products WHERE active=1 ORDER BY code"):
                            stream.write((canonical({"code": row["code"], "export_id": row["export_id"],
                                "source": json.loads(zlib.decompress(row["raw_zlib"])),
                                "food": json.loads(row["food_json"]) if row["food_json"] else None,
                                "licence": LICENCE}) + "\n").encode("utf-8"))
                    return
                else:
                    self.respond(404, {"error": "not-found"})
                    return
                self.respond(200, payload)
            except (ValueError, TypeError):
                self.respond(400, {"error": "invalid-request"})
            except (BrokenPipeError, ConnectionResetError, TimeoutError):
                pass
            except Exception:
                # Neither product contents nor queries are put in errors/logs.
                self.respond(503, {"error": "catalogue-unavailable"})
            finally:
                if db is not None:
                    db.close()
                slots.release()

    class Server(ThreadingHTTPServer):
        daemon_threads = True

        def process_request(self, request, address):
            # Bound threads too: waiting on the semaphore inside the handler
            # alone would still allow unbounded connection/thread allocation.
            if not self.connection_slots.acquire(blocking=False):
                request.close()
                return
            try:
                super().process_request(request, address)
            except BaseException:
                self.connection_slots.release()
                raise

        def process_request_thread(self, request, address):
            try:
                super().process_request_thread(request, address)
            finally:
                self.connection_slots.release()

    api = Server((host, port), Handler)
    api.connection_slots = threading.BoundedSemaphore(16)
    return api


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8781)
    parser.add_argument("--allow-export", action="store_true")
    args = parser.parse_args()
    with create_server(args.database, args.host, args.port, args.allow_export) as server:
        server.serve_forever()
