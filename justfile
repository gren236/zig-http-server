run:
    zig run src/main.zig

run-dir:
    zig run src/main.zig -- --directory /tmp/ 

test:
    zig test src/http.zig
    hurl --test tests.hurl
