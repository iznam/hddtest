#!/bin/bash

fdisk /dev/$1  <<EOF
n
p
1

+1000G
w
EOF

