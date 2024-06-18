#!/bin/bash

readonly RESTIC_REST_SERVER="http://127.0.0.1:80"

restic -r rest:http://admin:12345678@127.0.0.1:80/ init