#!/bin/sh

sed -i \
    -e "s;%BACKEND_HOST%;$BACKEND_HOST;g" \
    -e "s;%BACKEND_PORT%;$BACKEND_PORT;g" \
    -e "s;%VCL%;$VCL;g" \
    /etc/varnish/mediawiki.vcl