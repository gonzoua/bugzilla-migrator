#!/bin/sh

LAST=`ls checkpoints/*.sql | tail -1`
dropdb -U pgsql bugs && psql -U pgsql template1 < $LAST
