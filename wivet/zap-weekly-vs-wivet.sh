#!/bin/bash
# Runs ZAP against wivet with default options, generates the report and issues a PR to update it
# Parameters:
#	-d docker-image		Name of the ZAP docker image to use, typically owasp/zap2docker-weekly or owasp/zap2docker-stable
#	-e expected-score	Expected score string
#	-n name				Base name to use for the result files
#	-t text				Text to use in the summary table for the add-ons installed
#	-z zap-options		Options to be passed directly to the ZAP command line call 

USAGE="Usage: $0 -d docker-image [-e expected-score] -n name [-t text] [-z zap-options]"

# Handle the options
docker=''
expected=''
name=''
text='Ajax'
zap_opt=''
score_opt=''

while getopts "ad:e:n:p:t:z:" optname
  do
    case "$optname" in
      "a")
        # Ajax Spider
        score_opt="-a"
        ;;
      "d")
        # Docker image (mandatory)
        docker=$OPTARG
        ;;
      "e")
        # The expected score string
        expected=$OPTARG
        ;;
      "n")
        # The name to use in the results files
        name=$OPTARG
        ;;
      "t")
        text=$OPTARG
        ;;
      "z")
        # ZAP command line options
        zap_opt=$OPTARG
        ;;
      "?")
        echo "Unknown option $OPTARG"
        ;;
      ":")
        echo "No argument value for option $OPTARG"
        ;;
      *)
      # Should not occur
        echo "Unknown error while processing options"
        ;;
    esac
  done
# Check for the mandatory ones
if [ "$docker" == "" ]
then
  echo "Missing docker"
  echo $USAGE
  exit 2
fi
if [ "$name" == "" ]
then
  echo "Missing name"
  echo $USAGE
  exit 2
fi

# Git stuff
git config --global user.name "zapbot"
git config --global user.email "zapbot@zaproxy.org"

# Download and start new docker instances

docker pull andresriancho/wivet
WSCID=$(docker run -d -p 443:443 andresriancho/wivet)

IP=$(docker inspect $WSCID | grep IPAddress | tail -1)
IP=$(echo $IP | awk '{print substr($0,15)}')

WSIP=$(echo ${IP::-2})
echo Wivet IP = $WSIP

docker pull ${docker}
ZPCID=$(docker run -u zap -p 8090:8090 -d ${docker} zap-x.sh -daemon -port 8090 -host 0.0.0.0 -config api.disablekey=true -config ajaxSpider.clickDefaultElems=False $zap_opt)

IP=$(docker inspect $ZPCID | grep IPAddress | tail -1)
IP=$(echo $IP | awk '{print substr($0,15)}')

ZPIP=$(echo ${IP::-2})
echo ZAP IP = $ZPIP

echo Let ZAP start up...
sleep 20

# Spider and scan the app
python ~/zap-mgmt-scripts/wivet/wivet-spider-ajax.py -n ${name} -z $ZPIP -w $WSIP > result

# Save the logs
LOG="~/zap-mgmt-scripts_gh-pages/reports/${name}.logs.txt"
docker logs $ZPCID > ~/zap-mgmt-scripts_gh-pages/reports/${name}.logs.txt

echo "<tr>" > ${name}.summary
echo "<td>" `cat result | grep ZAP | awk -F ' ' '{print $2}'` "</td>" >> ${name}.summary

echo "<td>wivet</td>" >> ${name}.summary
echo "<td>${text}</td>" >> ${name}.summary
echo "<td>-</td>" >> ${name}.summary

echo "<td>" `date --rfc-3339 date` "</td>" >> ${name}.summary
echo "<td><a href=\"reports/${name}.html\">" `cat result | grep Score | awk -F ' ' '{print $2}'` " &#37;</a></td>" >> ${name}.summary
echo "<td>" `cat result | grep Pages | awk -F ' ' '{print $2}'` "</td>" >> ${name}.summary
echo "<td>" `cat result | grep Time | awk -F ' ' '{print $2}'` "</td>" >> ${name}.summary

ERRS=$(grep -c ERROR ~/zap-mgmt-scripts_gh-pages/reports/${name}.logs.txt) >> ${name}.summary
echo "<td><a href=\"reports/${name}.logs.txt\">${ERRS}</a></td>" >> ${name}.summary
echo "</tr>" >> ${name}.summary

cat ${name}.summary

# If present ~/.awssns should contain the AWS SNS topic to post to
AWSSNSF=$(echo ~/.awssns)

# TODO SC is never set up ;)
if [ "$SC" != "$expected" ]; then
  # Unexpected score, send an alert
  AWSSNS=$(cat ~/.awssns)
  aws sns publish --subject "ZAP ${name} Unexpected score" --message "Expected $expected got $SC" --topic $AWSSNS
fi

# Save and push to github
mv ${name}.summary ${name}.html wivet-style.css ~/zap-mgmt-scripts_gh-pages/reports/

cd ~/zap-mgmt-scripts_gh-pages
git add reports

cat scan.head reports/*.summary scan.tail > scans.html
git add scans.html

git commit -m "Report ${name}"
git push origin

