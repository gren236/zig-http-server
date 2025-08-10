GET http://localhost:4221
HTTP 200

GET http://localhost:4221/echo/abcd
HTTP 200
[Asserts]
header "Content-Type" == "text/plain"
header "Content-Length" == "4"

GET http://localhost:4221/user-agent
User-Agent: hello-world
HTTP 200
[Asserts]
header "Content-Type" == "text/plain"
header "Content-Length" == "11"
body contains "hello-world"

# Test files
POST http://localhost:4221/files/hello.txt
Content-Type: application/octet-stream
Content-Length: 13
`hello, world!`
HTTP 201

GET http://localhost:4221/files/hello.txt
HTTP 200
[Asserts]
header "Content-Type" == "application/octet-stream"
header "Content-Length" == "13"
body contains "hello, world!"

# Test compression
GET http://localhost:4221/echo/abc
Accept-Encoding: gzip
HTTP 200
[Asserts]
header "Content-Encoding" == "gzip"

GET http://localhost:4221/echo/abc
Accept-Encoding: invalid-encoding
HTTP 200
[Asserts]
header "Content-Encoding" not exists

GET http://localhost:4221/echo/abc
Accept-Encoding: invalid-encoding-1, gzip, invalid-encoding-2
HTTP 200
[Asserts]
header "Content-Encoding" == "gzip"

GET http://localhost:4221/echo/abc
Accept-Encoding: invalid-encoding-1, invalid-encoding-2
HTTP 200
[Asserts]
header "Content-Encoding" not exists
