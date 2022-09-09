#!/usr/local/bin/bash

#************************************************
# FUNCTIONS
#************************************************
function get_options() {
  while getopts ":hk:f:" option
  do
    case ${option} in
      f)
        file_name_json="${OPTARG}";
        verify_json_file
        ;;
      k)
        api_key="${OPTARG}";
        verify_api_key
        ;;
      h)
        clear;
        echo "Usage:";
        echo "           Mandatory                        [-f] Path to 'diagnostic_report.json'";
        echo "           Optional                         [-k] API key for 'https://network.pivotal.io'";
        exit;
        ;;
     \?)
        echo "Error in command line parsing.";
        exit;
        ;;
      esac
  done
}

function verify_api_key() {
  auth_code=$(curl -X GET https://network.tanzu.vmware.com/api/v2/authentication -H "Authorization: $api_key" | jq '.status')
  
  if [ $auth_code == 401 ]
  then
    echo "Unable To Verify API Key. Exiting Now..."
    exit;
  elif [ $auth_code == 200 ]
  then
    echo "Continuing.."
  else
    echo "Unknown Error. Exiting."
    exit;
  fi
}

function verify_json_file() {
  if [ -z "$file_name_json" ]
  then
    echo "You need a file name.";
  elif [ -f $file_name_json ]
  then
    if jq empty $file_name_json 2> /dev/null
    then
      return 1;
    else
      echo "File $file_name_json Is NOT Valid.";
      exit;
    fi
  else
    echo "File $file_name_json No Exist. Please verify path.";
  fi
}

function known_product_slugs_with_different_url() {
  declare -A errSlug=(
    ["p-healthwatch2"]="p-healthwatch"
    ["p-healthwatch2-pas-exporter"]="p-healthwatch"
    ["metric-store"]="p-metric-store"
    ["appMetrics"]="apm"
  )
  
  for index in ${!errSlug[@]}
  do
    if [[ "$index" == "$product_name" ]]
    then
      product_name="${errSlug[$index]}"
      return 0
    fi
  done
}



#************************************************
# MAIN
#************************************************
get_options $@
today_date=$(date +"%Y-%m-%d")

rm -f main.csv
rm -f diagnostic_report_all.*
rm -f diagnostic_report_eogs.*
rm -f diagnostic_report_supported.*


# Parsing the diagnostic file from the support bundle(s)
for product_name in $(jq '.added_products.deployed[] | .name' $file_name_json | sed 's/"//g')
do
  
  # Get Product Version Of Current Product Name
  product_version=$(jq ".added_products.deployed[] | select(.name==\"${product_name}\") | .version" $file_name_json | awk -F "-" '{ print $1 }' | sed 's/"//g')
  
  # Checking Slugs
  known_product_slugs_with_different_url
  
  is_error=$(curl -X GET https://network.tanzu.vmware.com/api/v2/product_details/$product_name | jq ".status")

  if [[ $is_error != 404 ]]
  then
    # Get End Of General Support Date
    product_eogs=$(curl -X GET https://network.tanzu.vmware.com/api/v2/product_details/$product_name | jq ".releases[] | select(.version==\"${product_version}\") | .end_of_support_date" | sed 's/"//g')  
  
    # DISPLAY
    # Get Todays Date
    today_epoch_date=$(date -j -f "%Y-%m-%d" $today_date "+%s")
    
    product_eogs_epoch_date=$(date -j -f "%Y-%m-%d" $product_eogs "+%s")
    
    if [[ $product_eogs_epoch_date < $today_epoch_date ]];
    then
      echo "$product_name,$product_version,$product_eogs,$product_eogs_epoch_date" >> diagnostic_report_all.csv
      echo "$product_name,$product_version,$product_eogs,$product_eogs_epoch_date" >> diagnostic_report_eogs.csv
    else
      echo "$product_name,$product_version,$product_eogs,$product_eogs_epoch_date" >> diagnostic_report_all.csv
      echo "$product_name,$product_version,$product_eogs,$product_eogs_epoch_date" >> diagnostic_report_supported.csv
    fi
  else
    # There's some error with the EOGS date
    echo "$product_name,$product_version,$product_eogs" >> main.csv
  fi
done
