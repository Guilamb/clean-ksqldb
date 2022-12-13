# clean-ksqldb

This is a simple bash tool, that allow you to delete every table, streams and topics of ksqldb.
```
 Script usage: ./clean-ksql [-OPTION]
 -v | --verbose :        Activate verbose
 -h | --help    :        Display help
 -o :
        streams  :        Delete only streams, will fail il table are using some of the streams
        tables   :        Delete only tables,
        all     :        Delete tables and streams
 -t | --topics  :        Delete topics, but don't remove topic named metrics or internals topics
 --server       :        Set server address

```
