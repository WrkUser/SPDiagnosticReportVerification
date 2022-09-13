#!/usr/local/bin/bash

#***********************************
# FUNCTIONS
#***********************************
function __main__() {
  # VARIABLES
  local option="";
  local file_name="";
  local auth_pivnet_url="https://network.tanzu.vmware.com/api/v2/authentication";
  local product_pivnet_url="https://network.tanzu.vmware.com/api/v2/product_details";
  local product_name="";
  local product_version="";
  local product_pivnet_slug="";
  local obj_jq="";
  local counter=0;
  
  # BODY
  rm -f diagnostic_report_all*
  rm -f diagnostic_report_eogs*
  rm -f diagnostic_report_supported*
  
  while getopts ":hk:f:" option
  do
    case ${option} in
      f)
        if verify_json_file "${OPTARG}"
        then
          file_name="${OPTARG}"
        else
          echo "Error with the return value while verifying json file."
        fi
      ;;
      k)
        clear;
        echo "This API feature feature is pending.";
        echo "Please remove this option, and try again.";
        exit;
      ;;
      h)
        clear;
        echo "Usage:";
        echo "                  Mandatory                      [-f] Path to 'diagnostic_report.json'";
        echo "                  Optional                       [-k] API key for 'http://network.pivotal.op'";
        exit;
      ;;
      \?)
        echo "Error in command line parsing.";
        exit;
      ;;
      esac
  done
  
  for product_name in $(jq '.added_products.deployed[] | .name' $file_name | sed 's/"//g')
  do
    product_version=$(jq ".added_products.deployed[] | select(.name==\"${product_name}\") | .version" $file_name | awk -F "-" '{ print $1 }' | sed 's/"//g')
    product_pivnet_slug="$product_name"
    counter=0
    
    while [ $counter -le 1 ]
    do
      obj_jq=$(curl -X GET "$product_pivnet_url/$product_pivnet_slug" --silent)
      
      if [[ $(echo "$obj_jq" | jq ".status") != 404 ]]
      then
        fx_tmp_name $product_name $product_version "$obj_jq"
        break;
      else
        if [[ $counter -eq 0 ]]
        then
          product_pivnet_slug=$(checkPivnetName $product_name)
        else
          echo "Unable to solve the Product Pivnet Slung Name for Product: $product_name"
        fi
        counter=$((counter+1))
      fi
    done
  done
}

function fx_tmp_name () {
  # variables
  local product_name=$1
  local product_version=$2
  local obj_jq=$3
  local today_is=$(date +"%Y-%m-%d")
  local product_id=""
  local product_eogs_date=""
  
  # body
  product_eogs_date=$(echo "$obj_jq" | jq ".releases[] | select(.version==\"${product_version}\") | .end_of_support_date" | sed 's/"//g')
  product_id=$(echo "$obj_jq" | jq ".releases[] | select(.version==\"${product_version}\") | .id" | sed 's/"//g')
  
  if $(checkDate $product_eogs_date)
  then
    if [[ $product_eogs_date < $today_is ]]
    then
      generateJSON 'diagnostic_report_all.json' $product_id $product_pivnet_slug $product_name $product_version $product_eogs_date
      generateJSON 'diagnostic_report_eogs.json' $product_id $product_pivnet_slug $product_name $product_version $product_eogs_date
    elif [[ $product_eogs_date == $today_is ]]
    then
      generateJSON 'diagnostic_report_all.json' $product_id $product_pivnet_slug $product_name $product_version $product_eogs_date
      generateJSON 'diagnostic_report_eogs.json' $product_id $product_pivnet_slug $product_name $product_version $product_eogs_date
      generateJSON 'diagnostic_report_supported.json' $product_id $product_pivnet_slug $product_name $product_version $product_eogs_date
    else
      generateJSON 'diagnostic_report_all.json' $product_id $product_pivnet_slug $product_name $product_version $product_eogs_date
      generateJSON 'diagnostic_report_supported.json' $product_id $product_pivnet_slug $product_name $product_version $product_eogs_date
    fi
  else
    echo "Error with product eogs date which is $product_eogs_date, with a product name of $product_name using version $product_version"
    echo "    $product_pivnet_url/$product_name"
  fi
}

function generateJSON () {
  # variables
  local file=$1
  local product_id=$2
  local product_pivnet_slug=$3
  local product_name=$4
  local product_version=$5
  local product_eogs_date=$6
  local tanzu_network_url="https://network.pivotal.io/products/$product_name/releases/$product_id"
  
  # body
  if [ ! -f $file ]
  then
    echo '{}' > $file
  fi
  
  echo "$(jq ".deployed += [{ \"id\": \"$product_id\", \"pivnet_slug\": \"$product_pivnet_slug\", \"name\": \"$product_name\", \"version\": \"$product_version\", \"eogs_date\": \"$product_eogs_date\", \"url\": \"$tanzu_network_url\" }]" $file)" > $file
}

function checkDate () {
  # variables
  local idate=$1
  
  # body
  if [[ $idate =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
  then
    true
  else
    false
  fi
}

function checkPivnetName () {
  # variables
  local product_name=$1
  declare -A pivnet_slug_arr=(
    ["p-healthwatch2"]="p-healthwatch"
    ["p-healthwatch2-pas-exporter"]="p-healthwatch"
    ["metric-store"]="p-metric-store"
    ["appMetrics"]="apm"
    ["p-antivirus"]="p-clamav-addon"
    ["p-antivirus-mirror"]="p-clamav-addon"
  )
  
  for index in ${!pivnet_slug_arr[@]}
  do
    if [[ "$index" == "$product_name" ]]
    then
      echo "${pivnet_slug_arr[$index]}"
      return 1;
    fi
  done
  
  # If product name is not in the dictionary it outputs the f(x) input
  echo "$product_name"
}

function verify_json_file () {
  # variable
  local file_name=$1
  
  # body
  if [[ -z $file_name ]]
  then
    echo "You need a file name.";
    exit;
  elif [[ -f $file_name ]]
  then
    if jq empty $file_name 2> /dev/null
    then
      true;
    else
      echo "File $file_name is NOT valid JSON file.";
      exit;
    fi
  else
    echo "File $file_name Does Not Exist! Please verify file path.";
    exit;
  fi
}



#***********************************
# MAIN
#***********************************
__main__ $@
