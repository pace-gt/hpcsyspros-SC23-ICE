#!/bin/bash

# The input files are plaintext, formatted like:
# username UID_Number Affiliation
# where the 1st two are standard system uid and username
# and the 3rd is taken from affiliation defined in LDAP

cat pace_ice_homedirs_to_cp | xargs -P 30 -L 1 ./create_for_xargs.sh hpaceice1 
cat coc_ice_homedirs_to_cp | xargs -P 30 -L 1 ./create_for_xargs.sh hcocice1 
