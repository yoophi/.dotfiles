#!/bin/bash

SANDBOX_DIR=$HOME/sandbox/$(date +%F)

mkdir -p $SANDBOX_DIR
cd $SANDBOX_DIR

exec $SHELL

