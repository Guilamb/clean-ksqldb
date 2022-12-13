#!/bin/bash
######################################################################################################
# Script usage: ./clean-ksql [-OPTION]
# -v | --verbose :        Activate verbose
# -h | --help    :        Display help
# -o :
#        streams  :        Delete only streams, will fail il table are using some of the streams
#        tables   :        Delete only tables,
#        all     :        Delete tables and streams
# -t | --topics  :        Delete topics, but don't remove topic named metrics or internals topics
# --server       :        Set server address
#
########################################################################################################

#--- Colors and styles
export RED='\033[1;31m'
export YELLOW='\033[1;33m'
export GREEN='\033[1;32m'
export STD='\033[0m'
export BOLD='\033[1m'
export REVERSE='\033[7m'

#--- Scripts parameters
KSQL_ENDPOINT="http://cp-ksql-server:8088"
REGEX="Cannot drop*"

#--- Get and validate the provided input
readOptions(){
  local options
  if ! options="$(getopt -o "vho:t" --long "server:,help,verbose,topics" -a -- "$@")"; then
    exit 1
  fi
  eval set -- "${options}"

  while true; do
    case "$1" in
      "-h"|"--help")
        printf "script usage: ./clean-ksql [-OPTION]"
        printf " -v | --verbose :\tActivate verbose\n"
        printf " -h | --help    :\tDisplay help\n"
        printf "%s\n \tstreams  :\t%s\n \ttables   :\t%s\n \tall     :\t%s\n" " -o :" " Delete only streams, will fail il table are using some of the streams" " Delete only tables", " Delete tables and streams"
        printf " -t | --topics  :\tDelete topics, but don't remove topic named metrics or internals topics\n"
        printf " --server       :\tSet server address\n"
        exit 0 ;;

      "-o")
        case "$2" in
          "tables"|"table") tableDrop=true ;;
          "streams"|"stream") streamDrop=true ;;
          "all") tableDrop=true ; streamDrop=true ;;
          *) printf "unrecognized argument" ; exit 1 ;;
        esac ;;

      "--server") KSQL_ENDPOINT="$2" ; shift ;;
      "-t"|"--topics") dropTopics=true ;;
      "-v"|"--verbose") verbose=true ;;
      --) shift ; break ;;
    esac
    shift
  done
}

#--- Display loading bar
LoadBar(){
  current=$((($1*100)/$2))
  printf "%-*s" $((current+1)) '[' | tr ' ' '#'
  printf "%*s%3d%%\r"  $((100-current))  "]" "${current}"
}

#--- Initialize variable
initVars(){
  printf "\n%bInitializing (should take a while)...%b\n" "${REVERSE}${YELLOW}" "${STD}"
  LoadBar "1" "6"
  jq --version 1> /dev/null
  if [ -z $? ]; then
  # mettre en rouge avec ERROR
    printf "JQ Not found. Please install jq before running this script : https://github.com/stedolan/jq" ; exit 1
  fi

  LoadBar "2" "6"
  ksql http://cp-ksql-server:8088 -e "SHOW PROPERTIES;" &>/dev/null;
  if [ $? -ne 0 ]; then
      printf "%bERROR : Can't join ksql server.\n Please check that you set a correct endpoint using --server if not using default ksql endpoint%b\n" "${RED}" "${STD}" ; exit 1
  fi

  LoadBar "3" "6"
  tables="$(ksql ${KSQL_ENDPOINT} --output JSON -e "show tables;" 2> /dev/null | jq -r .[].tables[].name | sed "s/[:space]/N/")"
  LoadBar "4" "6"
  streams="$(ksql ${KSQL_ENDPOINT} --output JSON -e "show streams;" 2> /dev/null | jq -r .[].streams[].name)"
  LoadBar "5" "6"
  terminateQueries
  LoadBar "6" "6"
}

#--- Terminate queries that might be running
terminateQueries(){
  ksql ${KSQL_ENDPOINT} -e "TERMINATE ALL" > /dev/null 2>&1;
}

#--- Delete all tables
deleteAllTables(){
  nbTable="$(echo "${tables[@]}" | wc -w)"
  currentTable=1
  printf "\n%bDropping tables...%b\n" "${REVERSE}${YELLOW}" "${STD}"

  #--- Check all tables in the list
  while [ -n "${tables}" ]; do
    for table in ${tables}; do
      tables_error=""

      #--- Delete the table of ksqldb
      if [ $dropTopics ]; then
        tables_error="$(ksql ${KSQL_ENDPOINT} -e "drop table ${table} delete topic;" 2> /dev/null)"
        if [[ "${tables_error}" =~  "Refusing to delete topic"* ]]; then
          printf "%bcan't delete topic associated with \"${table}\" because it is used by another object%b\n" "${YELLOW}" "${STD}"
          undroppedTopics+="$(echo "${tables_error}" | grep -Poe "(?<=using topic) [[:alpha:]]*")"
          tables_error="$(ksql ${KSQL_ENDPOINT} -e "drop table ${table};" 2> /dev/null)"
        fi
      else
        tables_error="$(ksql ${KSQL_ENDPOINT} -e "drop table ${table};" 2> /dev/null)"
      fi

      #--- if an error is returned, and match with expected error
      # Note : don't change format to "${tables_error}"
      if [[ "${tables_error}" =~ ${REGEX} ]]; then
        if [ ${verbose} ]; then
          echo "${tables_error}"
        fi  
      else
        LoadBar ${currentTable} ${nbTable}
        ((currentTable++))

        #--- if no error is detected, we delete the table of the list
        tables="$(echo "${tables}" | sed "/${table}/d")"

        if [ ${verbose} ]; then
          printf "-----list of tables-----\n${tables}\n"
        fi
      fi
    done
  done
  printf "\n%bTables dropped successfully.%b\n" "${GREEN}" "${STD}"
}

#--- Delete all streams
deleteAllStreams(){
  nbStream="$(echo "${streams[@]}" | wc -w)"
  currentStream=1

  if [[ -n ${tables} ]] && [[ ! ${tableDrop} ]]; then
  print
    printf "\n%bSome tables are attached to streams.\nPlease drop streams before.%b\n" "${RED}" "${STD}" ; exit 1
  fi

  printf "\n%bDropping streams...%b\n" "${REVERSE}${YELLOW}" "${STD}"

  #--- Check all streams in the list
  while [ -n "${streams}" ]; do
    for stream in ${streams}; do
      streams_error=""

      # --- Delete the table of ksqldb
      if [ ${dropTopics} ]; then
        streams_error="$(ksql ${KSQL_ENDPOINT} -e "drop stream ${stream} delete topic;" 2> /dev/null)"
        if [[ "${streams_error}" =~  "Refusing to delete topic"* ]]; then
          printf "\n%bCan't delete topic associated with \"${stream}\" because it is used by another object%b\n" "${YELLOW}" "${STD}"
          undroppedTopics+="$(echo "${streams_error}" | grep -Poe "(?<=using topic) [[:alpha:]]*")"
          streams_error="$(ksql "${KSQL_ENDPOINT}" -e "drop stream ${stream};" 2> /dev/null)"
        fi
      else
        streams_error="$(ksql "${KSQL_ENDPOINT}" -e "drop stream ${stream};" 2> /dev/null)"
      fi

      # --- Delete the table from the list
      if [[ "${streams_error}" =~ ${REGEX} ]]; then
        if [ ${verbose} ]; then
          printf "streams_error: [${streams_error}]"
        fi
      else
        LoadBar ${currentStream} ${nbStream}
        ((currentStream++))
        streams="$(echo "${streams}" | sed "/${stream}/d")"

        if [ ${verbose} ]; then
          printf  "-----list of streams-----\n[${streams}]\n"
        fi
      fi
    done
  done
  printf "\n%bStreams dropped successfully.%b\n" "${GREEN}" "${STD}"
  if [ -n "${undroppedTopics}" ]; then
    printf "following topics haven't been dropped: \"${undroppedTopics}\""
  fi
}

#--- Main
readOptions "$@"

if [[ ! ${tableDrop} ]] && [[ ! ${streamDrop} ]]; then
  printf "%bERROR : No argument specified.\nPlease see -h for helps%b\n" "${RED}" "${STD}" ; exit 1
fi

initVars

if [ ${tableDrop} ]; then
  deleteAllTables
fi

if [ ${streamDrop} ]; then
  deleteAllStreams
fi
