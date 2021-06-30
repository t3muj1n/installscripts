#!/bin/bash

## this takes the full mac address, cuts out the stuff we dont need and formats it for the post-data ##
## released under the dont be a dick license by mike robinson ##


arg1=$1;
xeq='x=';
oui=`echo $arg1 | cut -d":" -f 1,2,3 --output-delimiter="-"`;

wget  --post-data=""$xeq""$oui"" -q -O- http://standards.ieee.org/cgi-bin/ouisearch \
| sed -n '/^$/!{s/<[^>]*>//g;p;}';

## include this to get rid of the shitty multiline output from DOCTYPE ##
## there has got to be a better way to do this ##
##grep -v "<!DOCTYPE html" | grep -v "PUBLIC" | grep -v "www.w3.org" | grep -v "Search Results" ;##

## this might end up being done better with lynx --dump. something to think about ##
  


