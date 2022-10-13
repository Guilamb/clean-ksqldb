# clean-ksqldb

This is a simple bash tool, that allow you to delete every table, streams and topics of ksqldb.
```
script usage: $0 [-v] [-h] [-o] -[t] [--server-name]

  -v | --verbose : Activate verbose

  -h | --help : Display help

  -o :

   stream : Delete only streams, will fail il table are using some of the streams,

   table : Delete only tables,

   all : Delete tables and streams

  -t | --topics : delete topics, but don't remove topic named metrics or internals topics

  --server : set server address
```
