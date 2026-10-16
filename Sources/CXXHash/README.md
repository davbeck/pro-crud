# xxHash checksum bridge

Unmodified upstream `xxhash.h`, version **0.8.2**, from
https://github.com/Cyan4973/xxHash/blob/v0.8.2/xxhash.h.

SHA-256: `be275e9db21a503c37f24683cdb4908f2370a3e35ab96e02c4ea73dc8e399c43`.
The small declaration and bridge expose XXH3 to Swift for checksum validation
of native RocksDB block-format-5 MediaStore tables. This does not link RocksDB or
provide a database writer. The upstream BSD 2-Clause notice is in the header and
LICENSE.txt; distribute that notice with the CLI and installer.
