#!/bin/bash

function list_instances() {
    incus list --columns n --format csv
}

function export_instance() {
    incus export --instance-only
}