shellexec
=====

HTTP job processing service.

***
## Table of contents
* [API Endpoints](#api-endpoints)
  * [Process](#process)
  * [Generate bash script](#script)
* [Build](#build)
* [Run local server](#shell)
* [Run EUnit Tests](#test)
***
## API Endpoints
API support only POST requests
##### Body example
```json
{
  "tasks": [
    {
      "name": "task-1",
      "command": "touch /tmp/file1"
    },
    {
      "name": "task-2",
      "command": "cat /tmp/file1",
      "requires": [
        "task-3"
      ]
    },
    {
      "name": "task-3",
      "command": "echo 'Hello World!' > /tmp/file1",
      "requires": [
        "task-1"
      ]
    },
    {
      "name": "task-4",
      "command": "rm /tmp/file1",
      "requires": [
        "task-2",
        "task-3"
      ]
    }
  ]
}
```
* ##### Process
```shell script
curl --location --request POST 'http://127.0.0.1:8080' \
--header 'Content-Type: application/json' \
--data-raw '{{BODY}}'
```
* ##### Generate bash script
```shell script
curl --location --request POST 'http://127.0.0.1:8080/script' \
--header 'Content-Type: application/json' \
--data-raw '{{BODY}}'
```
***
## Build
-----

    $ rebar3 compile
***
## Shell
-----

    $ rebar3 shell

## Test
-----

    $ rebar3 eunit
***
