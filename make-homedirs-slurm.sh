#!/bin/bash

# Defaults
PATH=/bin:/usr/sbin:/usr/bin:/root/bin
DOTFILES=/path-to-scripts/dotfiles/. # nothing special in here
SLURM_LOG="path-to-slurm_accounts-log"
CREATEFAKEDATADIR=0
LOCK_FILE=/tmp/slurm-mkhomedirs.lock

# Functions

usage()
{
    echo "usage: make-homedirs-slurm.sh"
    echo "Optional: "
    echo "Dry run (indicate which directories will be made without them): --dryrun"
    echo "Silent mode: --silent (No echo to stdout)"
}

# Main

SILENT='false'

USERGROUPS="school1-deptA-ice-instructors school2-deptA-ice-instructors school1-deptB-ice-instructors school2-deptB-ice-instructors deptA-ice-access deptB-ice-access ice-access"

SYSTEM="ice-dev"
ICEHOME="home-mount-point"
ICESCRATCH="scratch-mount-point"
SACCTMGR="/usr/bin/sacctmgr"

while [ "$1" != "" ]; do
    case $1 in 
    -d | ---fakedatadirectory )
    	shift
        CREATEFAKEDATADIR=$1
        ;;
    --dryrun )
        DRYRUN='true'
        ;;
    --silent )
        SILENT='true'
        ;;
    -h | --help )
        usage
        exit
        ;;
    * )
        usage
        exit 1
    esac
    shift
done


if [ "$DRYRUN" == 'true' ]
then 
# Make sure all slurm commands do nothing
    SACCTMGR="echo ${SACCTMGR}"
    if [  "$SILENT" != 'true' ]
    then
        echo "Dryrun."
    fi
fi

if [[ -f ${LOCK_FILE} ]]; then
    echo "ERROR: Lock file ${LOCK_FILE} still exists! Check for running process."
    exit 1
fi
touch ${LOCK_FILE}

#Set up ldapsearch
if [ ! -e /usr/bin/ldapsearch ]; then
        echo "ERROR: ldapsearch is not available" >&2
        rm ${LOCK_FILE}
        exit 2
fi

#awk filter for LDAP data to put things on 1 line for easy consumption
# This is highly idiosyncratic, but possibly illustrutory
LDAP_PARSE='
$1=="UserID" {entitlements=""; name=gensub(/^ +/,"",1,$NF);} \
$1=="UserIdNumber" {uid=gensub(/^ +/,"",1,$NF);} \
$1=="GroupID" {gid=gensub(/^ +/,"",1,$NF);} \
$1=="Entitlements" && $2 ~ /-ice.+enabled$/ {ents=gensub(/^.+\/([a-z-]*-ice[a-z-]*)\/.+$/,"\\1","g",$2) " " ents;} 
$1=="Marker" {acctmarker=1}
$1=="AccountType" && $2==" dept" {dept=gensub(/^ +/,"",1,$NF)}
$1=="AccountType" && $2==" guest" {dept=gensub(/^ +/,"",1,$NF)}
/^$/ && acctmarker == 1 {acctmarker=0; 
  if (length(dept)==0) {dept="no-dept"}; 
  print name"|"uid"|"gid"|"dept"|"ents; dept=""; 
  name=""; uid=""; gid=""; ents="";}'

# Generate list of users in those groups for the larger ldap query
user_list=$(for USERGROUP in ${USERGROUPS}; \
 do getent group $USERGROUP | awk -F':' '{print $4}' | sed 's/,/ /g'; done)


#Grab departmental info from ldap for all our users for tracking via slurm
# store uidN Dept, and pace-ice entitlements by username
declare -g -A user_dept
declare -g -A user_uidn
declare -g -A user_gidn
declare -g -A user_ents

mapfile -t dept_uidN_list < <(ldapsearch -H "ldaps://your.local.ldap.url" -x -w "${PW}" \
 -D "uid=a-real-user,ou=Local Accounts,dc=your,dc=local,dc=DC" \
 -b "dc=your,dc=local,dc=dc" -LLL -f <(echo -e ${user_list} | tr ' ' '\n') \
 -c -o ldif-wrap=no uid=%s UserID UserIdNumber GroupID Entitlements AccountType \
 | awk -F':' "${LDAP_PARSE}")
for entry in "${dept_uidN_list[@]}"; do
    IFS='|' read -ra fields <<< "${entry}"
    user_uidn[${fields[0]}]="${fields[1]}"
    user_gidn[${fields[0]}]="${fields[2]}"
    user_dept[${fields[0]}]="${fields[3]}"
# Yes, this is _terrible_
    user_ents[${fields[0]}]=$(echo ${fields[4]} | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
    #echo ${fields[0]}: ${user_uidn[${fields[0]}]} ${user_gidn[${fields[0]}]} ${user_dept[${fields[0]}]} ${user_ents[${fields[0]}]}
done

#Next, gather existing slurm users, save qos and account info for checking against entitlements
declare -g -A slurm_default_qos
declare -g -A slurm_qos_list
declare -g -A slurm_default_account

mapfile -t slurm_user_list < <(${SACCTMGR} show associations -P -n -o format=User,account,qoslevel%50,defaultqos | awk -F'|' '$1 != "" {print $0}')
for entry in "${slurm_user_list[@]}"; do
    IFS='|' read -ra fields <<< "${entry}"
    slurm_default_account[${fields[0]}]="${fields[1]}"
    slurm_qos_list[${fields[0]}]="${fields[2]}"
    slurm_default_qos[${fields[0]}]="${fields[3]}"
    #echo "Existing slurm [${fields[0]}]: acct ${slurm_default_account[${fields[0]}]} qos ${slurm_qos_list[${fields[0]}]} def_qos ${slurm_default_qos[${fields[0]}]}"
done

for user in $(echo -e "${user_list}");
do

#Sadly, there are good reasons to keep this
    getent passwd $user > /dev/null
    if [ $? -eq 2 ]; then
        continue
    fi

    #First, handle Slurm Account Creation
    dept="${user_dept["${user}"]}"
    uidN="${user_uidn["${user}"]}"
    gidN="${user_gidn["${user}"]}"
    entitlements="${user_ents["${user}"]}"
    if [[ "${uidN}" == "" || "${gidN}" == "" ]]; then 
      echo "$(date): Missing UID ${uidN} or GID ${gidN} for ${user}" >> ${SLURM_LOG}
      continue
    fi

    #Set homedir based on last 2 digits of uid 
    USERHOME="${ICEHOME}${uidN: -2:1}/${uidN: -1}/${user}"
    #Set scratch dir based on last 2 digits of uid of username 
    USERSCRATCH="${ICESCRATCH}${uidN: -2:1}/${uidN: -1}/${user}"

    if [[ ${DRYRUN} == "true" && ${SILENT} == "false" ]]; then
      echo "For user: ${user} uid: $uidN gid: $gidN dept: $dept ents: $entitlements"
      echo "Making dirs: ${USERHOME} ${USERSCRATCH}"
    fi
    
    # Switch to using LDAP gidNumber
    # check valid gid - should be one of these by convention
    if [[ ! ($gidN == 1111 || $gidN == 2222 || $gidN == 3333 ) ]]; then
    # Previous behaviour defaulted to this, so that's what we'll continue for now
      gidN=1111
    fi
    #echo "for : $user : $uidN : $gidN : ${user_gidn["${user}"]} : $dept : $entitlements"
    #echo "creating : $USERHOME : $USERSCRATCH"

    # Set qos based on entitlement
    # - the order matters here! (slurm orders the list this way, no matter the input order)
    # Adding this for -students is basically the same flow; this has been shortened for redability
    max_qos_list="deptA-grade,deptA-ice,deptA-students,deptB-grade,deptB-ice"
    default_qos="deptB-ice"
    qos_list="deptB-ice"
    if [[ "${entitlements}" =~ "deptA-" ]]; then
        default_qos="deptA-ice"
        qos_list="deptA-ice"
    fi
    if [[ "${entitlements}" =~ "deptA-instructors" ]]; then
    # Add the -grade version of the default qos onto their list
    # - we put -grade 1st because slurm orders alphabetically...
        qos_list="deptA-grade,${qos_list}"
    fi
    if [[ "${entitlements}" =~ "deptB-instructors" ]]; then
        qos_list="deptB-grade,${qos_list}"
    fi

    if [[ ${DRYRUN} == "true" && ${SILENT} == "false" ]]; then
      echo "For user: ${user} ents: $entitlements"
      echo "Making qoslevel: ${qos_list} default_qos ${default_qos}"
    fi

    #SlurmEx -  Check if slurm user exists or not
    #if Not SlurmEx - Create slurm account
    (if [[ -z ${slurm_default_account["${user}"]} ]]; then
        #grab slurm error output, if we have a new dept coming in
        slurm_err=$(${SACCTMGR} add user -i name=${user} defaultaccount=${dept} qoslevel=${qos_list} defaultqos=${default_qos} maxsubmit=500 2>&1 >> ${SLURM_LOG})
        if [ "$SILENT" != 'true' ]; then
            logger -t "make-homdirs-slurm.sh" -p daemon.notice -- "${user} slurm user created on ${SYSTEM}";
        fi
        #create the account for the dept if it does not exist
        if [[ "${slurm_err}" =~ "doesn't exist" ]]; then
            ${SACCTMGR} -i create account name=${dept} organization=${dept} description="${dept} from ldap" qoslevel="${max_qos_list}" defaultqos="pace-ice" &>> ${SLURM_LOG};
            ${SACCTMGR} add user -i name=${user} defaultaccount=${dept} qoslevel=${qos_list} defaultqos=${default_qos} maxsubmit=500 &>> ${SLURM_LOG};
        fi
    #Else we must now check if account/qos are incorrect
    # satisfied by checking that default_qos matches slurm_default_qos and that
    #  slurm_default_account matches dept.
    elif [[ "${default_qos}" != "${slurm_default_qos["${user}"]}" || \
            "${qos_list}" != "${slurm_qos_list["${user}"]}" ]]; then
        ${SACCTMGR} modify user -i where name=${user} set qoslevel=${qos_list} defaultqos=${default_qos}  &>> ${SLURM_LOG}
        if [ "$SILENT" != 'true' ]; then
            logger -t "make-homdirs-slurm.sh" -p daemon.notice -- "${user} slurm user modified"
        fi
    # IF the department changes, we have to remove & re-add the user assoc...
    elif [[ "${dept}" != "${slurm_default_account["${user}"]}" ]]; then
        ${SACCTMGR} remove user -i where name=${user} and account=${slurm_default_account["${user}"]} &>> ${SLURM_LOG}
        slurm_err=$(${SACCTMGR} add user -i name=${user} defaultaccount=${dept} qoslevel=${qos_list} defaultqos=${default_qos} 2>&1 >> ${SLURM_LOG})
        if [[ "${slurm_err}" =~ "doesn't exist" ]]; then
            ${SACCTMGR} -i create account name=${dept} organization=${dept} description="${dept} from ldap" qoslevel="pace-ice" defaultqos="pace-ice" &>> ${SLURM_LOG}
            ${SACCTMGR} add user -i name=${user} defaultaccount=${dept} qoslevel=${qos_list} defaultqos=${default_qos} maxsubmit=500 &>> ${SLURM_LOG}
        fi
    fi)&
# We sleep a bit here to avoid overwhelming slurmdb, because you are NOT supposed to call sacctmgr in loops
    sleep 0.1

    # Make home directories if they do not exist. Populate the home directory with
    # the dot files. Set quota for user.
    if [ ! -d $USERSCRATCH ]; then
        if [ "$DRYRUN" != 'true' ]; then
            mkdir -p $USERSCRATCH
            chmod 700 $USERSCRATCH
	    chown -R ${uidN}:${gidN} $USERSCRATCH
            if [ "$SILENT" != 'true' ]; then
                logger -t "make-homdirs-slurm.sh" -p daemon.notice -- "${user} scratch space was created"
            fi
        fi
    fi
    if [ ! -d $USERHOME ]; then
        if [ "$DRYRUN" != 'true' ]; then
            mkdir -p $USERHOME
	    chmod 700 $USERHOME
	    cp -rn $DOTFILES $USERHOME
	    mkdir $USERHOME/.ssh
	    chmod 700 $USERHOME/.ssh/
	    ssh-keygen -b 4096 -t rsa -N '' -q -f $USERHOME/.ssh/id_rsa
	    cat $USERHOME/.ssh/id_rsa.pub >> $USERHOME/.ssh/authorized_keys
	    chmod 600 $USERHOME/.ssh/authorized_keys
	    chown -R ${uidN}:${gidN} $USERHOME
            if [ -d ${USERSCRATCH} ]; then
                ln -s ${USERSCRATCH} ${USERHOME}/scratch 
            else 
                if [ "$SILENT" != 'true' ]; then
                    logger -t "make-homdirs-slurm.sh" -p daemon.notice -- "${user} scratch FAILED to link"
                fi
            fi
            if [ "$SILENT" != 'true' ]; then
                logger -t "make-homdirs-slurm.sh" -p daemon.notice -- "${user} homedir was created"
            fi
	fi
    else #The homedir DOES exist, let's make sure it will *work*, because things happen...
        if [[ ! -h ${USERHOME}/scratch ]]; then
            ln -s ${USERSCRATCH} ${USERHOME}/scratch 
            chown -R ${uidN}:${gidN} ${USERHOME}/scratch 
        fi
        if [[ ! -f ${USERHOME}/.ssh/id_rsa ]]; then 
            mkdir -p $USERHOME/.ssh
            chmod 700 $USERHOME/.ssh/
            ssh-keygen -b 4096 -t rsa -N '' -q -f $USERHOME/.ssh/id_rsa
            cat $USERHOME/.ssh/id_rsa.pub >> $USERHOME/.ssh/authorized_keys
            chmod 600 $USERHOME/.ssh/authorized_keys
            chown -R ${uidN}:${gidN} $USERHOME/.ssh
        fi
        if [[ ! -f ${USERHOME}/.bashrc ]]; then
            cp -rn $DOTFILES $USERHOME
            chown -R ${uidN}:${gidN} $USERHOME
        fi
    # Make sure scratch link exists if Home does and scratch doesn't!
    fi
done

wait

rm ${LOCK_FILE}
