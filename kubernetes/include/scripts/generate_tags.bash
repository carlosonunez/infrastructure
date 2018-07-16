#!/usr/bin/env bash
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
TAGS_PATH="${TAGS_PATH?Please provide the path containing the tags to be created (in JSON form).}"
TERRAFORM_TFVARS_PATH="${TERRAFORM_TFVARS_PATH?Please provide the path to your Terraform variable inputs file.}"

_print_tags_with_trailing_commas_at_end_of_lists() {
  echo "$1" | \
    grep -v '^[ \t]\+$' | \
    tr '\n' '\f' | \
    sed 's#,\f]#\f]#g' | \
    sed 's#,\f}#\f}#g' | \
    tr '\f' '\n'
}

generate_key_value_tags() {
  json="${1?Please provide the JSON tree containing the tags to manipulate.}"
  echo -e "\n$(echo "$json" | \
    jq -r 'to_entries[] | .key + " = \"" + .value.value + "\","' | \
      sed 's/^/  /')\n"
}

generate_asg_compatible_tags() {
  json="${1?Please provide the JSON tree containing the tags to manipulate.}"
  echo -e "\n$(echo "$json" | \
    jq -r 'to_entries[] | "  {\n    key = \"" + .key + "\"\n    value = \"" + .value.value + "\"\n    propagate_at_launch = " + (.value.propagate|tostring) + "\n  },"' | \
      sed 's/^/  /')\n"
}

get_tags_json() {
  tag_file="${1?Please provide the tag file to read.}"
  tag_file_location="${TAGS_PATH}/${tag_file}.json"
  if [ ! -f "$tag_file_location" ]
  then
    >&2 echo "ERROR: File not found: $tag_file_location"
    return 1
  fi
  json=$(cat "$tag_file_location")
  environment_variables_found=$(echo "$json" | \
    grep -E '"\$[A-Z0-9_]{1,}"' | \
    sed 's/.*"\$\([A-Z0-9_]\+\)".*/\1/'
  )
  for environment_variable in $environment_variables_found
  do
    environment_variable_value="${!environment_variable}"
    if [ ! -z "$environment_variable_value" ]
    then
      json=$(echo "$json" | sed "s/\"\$${environment_variable}\"/\"$environment_variable_value\"/g")
    fi
  done
  echo "$json"
}

generate_tag_variables() {
  base_tags_json=$(get_tags_json "all")
  base_kvp_tags=$(generate_key_value_tags "$base_tags_json")
  base_asg_tags=$(generate_asg_compatible_tags "$base_tags_json")
  all_tags=$(cat <<BASE_TAGS
base_tags = {
  $base_kvp_tags
}
base_asg_tags = [
  $base_asg_tags
]
BASE_TAGS
)
  for tag_file in $TAGS_PATH/*
  do
    tag_file_name=$(basename "$tag_file" | sed 's/.json$//') 
    if [ "$tag_file_name" != "all" ]
    then
      tag_json=$(get_tags_json "$tag_file_name")
      kvp_tags=$(generate_key_value_tags "$tag_json")
      asg_tags=$(generate_asg_compatible_tags "$tag_json")
      all_tags=$(cat <<ADDITIONAL_TAGS
$all_tags
${tag_file_name}_tags = {
  $base_kvp_tags
  $kvp_tags
}
${tag_file_name}_asg_tags = [
  $base_asg_tags
  $asg_tags
]
ADDITIONAL_TAGS
)
    fi
  done

  _print_tags_with_trailing_commas_at_end_of_lists "$all_tags"
}

generate_tag_variables >> "$TERRAFORM_TFVARS_PATH"
