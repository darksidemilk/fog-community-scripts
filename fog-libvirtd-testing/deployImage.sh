#!/bin/bash


# This deploys an image to the specified VM, with a specified FOG ID.
# Required arguments are 1 the VM's name, 2 the VM's FOG ID.
# This script will deploy the pre-associated image with these FOG hosts only.


cwd="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$cwd/settings.sh"

# First argument is our vmname
vmname="$1"
# Second argument is the ID
fogid="$2"

# Ask for the VM guest name.
if [[ -z $vmname ]]; then
    echo "$(date +%x_%r) No vmGuest name passed for argument 1, exiting." >> $output
    exit
else
    vmGuest=$vmname
fi

# Ask for the FOG ID of the guest we are to use for deploy.
if [[ -z $fogid ]]; then
    echo "$(date +%x_%r) No vmGuestFogID passed for argument 2, exiting." >> $output
    exit
else
    vmGuestFogID=$fogid
fi

echo "$(date +%x_%r) Queuing deploy. vmGuest=\"${vmGuest}\" vmGuestFogID=\"${vmGuestFogID}"\" >> $output


#Make the hosts directory for logs on the share.
rm -rf ${shareDir}/${vmGuest}
mkdir -p ${shareDir}/${vmGuest}/screenshots
chown -R $sharePermissions $shareDir


# Headers
contenttype="-H 'Content-Type: application/json'"
usertoken="-H 'fog-user-token: ${testServerUserToken}'"
apitoken="-H 'fog-api-token: ${testServerApiToken}'"

# Body to send
body="'{\"taskTypeID\":1,\"shutdown\": true}'"

# URL to call
url="http://${testServerIP}/fog/host/${vmGuestFogID}/task"

# Queue the deploy jobs with the test fog server.
cmd="curl --silent -k ${contenttype} ${usertoken} ${apitoken} ${url} -d ${body}"
eval $cmd >/dev/null 2>&1 # Don't care that it says null.


sleep 5

# Reset the VM forcefully.
echo "$(date +%x_%r) Resetting \"${vmGuest}\" to begin deploy." >> ${output}
ssh -o ConnectTimeout=${sshTimeout} ${hostsystem} "virsh start \"${vmGuest}\"" >/dev/null 2>&1


count=0
#Need to monitor task progress somehow. Once done, should exit.
getStatus="${cwd}/getTaskStatus.sh ${vmGuestFogID}"
while [[ ! $count -gt $deployLimit ]]; do
    status=$($getStatus)
    nonsense=$(timeout $sshTime ssh -o ConnectTimeout=$sshTimeout $hostsystem "echo wakeup")
    nonsense=$(timeout $sshTime ssh -o ConnectTimeout=$sshTimeout $hostsystem "echo get ready")
    timeout $sshTime ssh -o ConnectTimeout=$sshTimeout $hostsystem "virsh screenshot $vmGuest /root/${vmGuest}_${count}.ppm" > /dev/null 2>&1
    timeout $sshTime scp -o ConnectTimeout=$sshTimeout $hostsystem:/root/${vmGuest}_${count}.ppm ${shareDir}/${vmGuest}/screenshots > /dev/null 2>&1
    timeout $sshTime ssh -o ConnectTimeout=$sshTimeout $hostsystem "rm -f /root/${vmGuest}_${count}.ppm" > /dev/null 2>&1

    if [[ $status -eq 0 ]]; then
        echo "$(date +%x_%r) Completed image deployment to \"${vmGuest}\" in about \"$((count / 2))\" minutes." >> ${output}
        echo "Completed image deployment to \"${vmGuest}\" in about \"$((count / 2))\" minutes." >> ${report}
        break
    fi
    let count+=1
    sleep $deployLimitUnit
done
if [[ $count -gt $deployLimit ]]; then
    echo "$(date +%x_%r) Image deployment did not complete within \"$((deployLimit / 2))\" minutes." >> ${output}
    echo "Image deployment did not complete within \"$((deployLimit / 2))\" minutes." >> ${report}
fi
nonsense=$(timeout ${sshTime} ssh -o ConnectTimeout=${sshTimeout} ${hostsystem} "echo wakeup")
nonsense=$(timeout ${sshTime} ssh -o ConnectTimeout=${sshTimeout} ${hostsystem} "echo get ready")
sleep 5
ssh -o ConnectTimeout=${sshTimeout} ${hostsystem} "virsh destroy \"${vmGuest}\"" >/dev/null 2>&1


