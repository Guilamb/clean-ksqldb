#! /bin/bash


flagReader(){
  local options
  # Call getopt to validate the provided input.

  if ! options="$(getopt -o "vho:t" --long "server:,help,verbose,topics" -a -- "$@")"; then
      exit 1;
  fi
  eval set -- "$options"

  while true; do
    case $1 in
      -v|--verbose)
        verbose=true
        ;;
      -h|--help)
        echo "script usage: $(basename \$0) [-v] [-h] [-o] -[t] [--server-name]"
        printf "%s\n" "-v | --verbose : Activate verbose"
        printf "%s\n" "-h | --help : Display help"
        printf "%s\n %s\n %s\n %s\n" "-o :", "stream : Delete only streams, will fail il table are using some of the streams", "table : Delete only tables", "all : Delete tables and streams"
        printf "%s\n" "-t | --topics : delete topics, but don't remove topic named metrics or internals topics"
        printf "%s\n" "--server : set server address"
        exit 0
        ;;
      -o)
        case $2 in
          table)
            echo "table activated"
            tableDrop=true
            ;;
          stream)
            echo "stream activated"
            streamDrop=true
            ;;
          all)
            echo "all activated"
            tableDrop=true
            streamDrop=true
            ;;
          *)
            echo "unrecognized argument"
            exit 1
            ;;
        esac
        ;;
      --server)
        hostname=$2
        shift
        ;;
      -t|--topics)
        echo "topics activated"
        dropTopics=true
        ;;
      --)
        shift
        break;;
      "-"*)
        echo "error, unrecognized flag. Please check help for more information"
        exit 1
        ;;
    esac
    shift
  done

}

# initialize variable
initial_vars(){
  hostname="http://cp-ksql-server:8088"
  jqVersion=$(jq --version)
  if [ -z "$jqVersion" ]; then
      echo "JQ Not found. Please install jq before running this script : https://github.com/stedolan/jq"
      exit 1
  fi


  topics=$(ksql $hostname --output JSON -e "show topics;"|jq -r .[].topics[].name )
  tables=$(ksql $hostname --output JSON -e "show tables;"|jq -r .[].tables[].name | sed "s/[:space]/N/")
  streams=$(ksql $hostname --output JSON -e "show streams;"|jq -r .[].streams[].name )

  terminate_queries

}
# Terminate queries that might be running
terminate_queries(){
    ksql $hostname -e "TERMINATE ALL" 1>/dev/null;
  }
# delete all tables
delete_tables(){
  regex="Cannot drop*"
  echo "Dropping tables..."
  # while there still tables in the list
  while [ -n "$tables" ]; do
  # for each table of the list
    for table in $tables; do
      tables_error=""

      # delete the table of ksqldb
      if [ $dropTopics ]; then
        tables_error=$(ksql $hostname -e "drop table $table delete topic;")
        if [[ $tables_error =~  "Refusing to delete topic"* ]]; then
          echo -e "\e[33can't delete topic associated with $table\e[0m"
            undroppedTopics+=$(echo $tables_error | grep -Poe "(?<=using topic) [[:alpha:]]*")
            tables_error=$(ksql $hostname -e "drop table $table;")
        fi
      else
          tables_error=$(ksql $hostname -e "drop table $table;")
      fi


      # if an error is returned, and match with expected error
      if [[ $tables_error =~ $regex ]]; then
        # we pass to the next table of the list
        continue
      else
        echo "dropping $table"

        # if no error is detected, we delete the table of the list
        tables=$(sed "/$table/d" <<< "$tables")

        if [ $verbose ]; then
          printf "-----list of tables-----\n"
          printf '%s\n' "$tables"
        fi

      fi
    done
  done
  echo -e "\e[32mtables dropped\e[0m"
}
# delete all streams
delete_streams(){
    regex="Cannot drop*"
    if [[ -n $tables ]] && [[ ! $tableDrop ]]; then
        echo -e "\e[31msome tables are attached to streams. Please drop streams before\e[0m"
        exit 1
    fi
    echo "Dropping streams..."
    # while there still tables in the list
    while [ -n "$streams" ]; do
    # for each table of the list
      for stream in $streams; do
        streams_error=""

        # delete the table of ksqldb
        if [ $dropTopics ]; then
          streams_error=$(ksql $hostname -e "drop stream $stream delete topic;")
          if [[ $streams_error =~  "Refusing to delete topic"* ]]; then
            echo -e "\e[33can't delete topic associated with $stream\e[0m"
              undroppedTopics+=$(echo $streams_error | grep -Poe "(?<=using topic) [[:alpha:]]*")
              streams_error=$(ksql $hostname -e "drop stream $stream;")
          fi
        else
          streams_error=$(ksql $hostname -e "drop stream $stream;")
        fi

        # if an error is returned, and match with expected error
        if [[ $streams_error =~ $regex ]]; then
          # we pass to the next table of the list
          echo "$streams_error"
          continue
        else
          echo "dropping $stream"
          echo "$streams_error"

          # if no error is detected, we delete the table of the list
          streams=$(sed "/$stream/d" <<< "$streams")

          if [ $verbose ]; then
            printf "%s\n" "-----list of streams-----"
            printf '%s\n' "$streams"
          fi

        fi
      done
    done
    echo -e "\e[32mstreams dropped\e[0m"
    if [ -n "$undroppedTopics" ]; then
        echo "following topics haven't been dropped: $undroppedTopics"
    fi
  }

flagReader "$@"

initial_vars

if [ $tableDrop ]; then
  delete_tables
fi
if [ $streamDrop ]; then
    delete_streams
fi



  # TODO
  #  * Verrifier si JQ est disponible sur la machine, sinon emettre une erreur OK
  #  * Ajouter la possibilité de terminer tous les  processus en cours OK
  #    * TERMINATE ALL
  #  * Add flag delete Streams, Tables, ALL ( set default to all ?? ) OK
  #  * Set Hostname in query OK
  #  * Drop topics but not metrics OK
  #  * Do a percentage instead of dropped table and stream ?
  #  * Errors are not treated for now OK
  #     * If flag encounter an error, it will continue OK
  #  * Delete $hostname in final version
  #  * See how it react when dropping a topic used by 2 different table/stream
  #     * See how to delete topic in that case

