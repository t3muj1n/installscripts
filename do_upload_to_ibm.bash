#!/usr/bin/env bash


#ibmcloud_login () {
#	ibmcloud login --sso
#};
#login to the ibm cloud environment 
ibmcloud_login () { 
	mypass='';   #set to your password
	mylogin=""  #usually your email addr.
	ibmcloud login -q -u "${mylogin}" -p "${mypass}" 
};
######################################################################
#some stuff needed for basic functionality with ibmcloud
get_resource_group () { target_resource="$(ibmcloud  resource groups --output json | jq .[].id | tr -d \")"; };
set_resource_group () { ibmcloud target -g "${target_resource}"; };
get_resource_crn () { resource_crn="$(ibmcloud resource service-instances --output json |jq .[].crn | tr -d \" )"; };
get_resource_name () { resource_name="$(ibmcloud resource service-instances --output json | jq .[].name | tr -d \")"; };
get_service_instance_id () { service_instance_id="$(ibmcloud resource service-instance "${resource_name}" --output json | jq .[].id | tr -d \")"; };
list_all_buckets () { ibmcloud cos list-buckets --ibm-service-instance-id "${service_instance_id}" --json; };
get_bucket_crn () { bucket_crn="$(ibmcloud resource service-keys --output json |jq .[].crn | tr -d \" )"; };
get_bucket_name () { bucket_name="$(ibmcloud resource service-keys --output json | jq .[].name | tr -d \")"; };
find_a_bucket () { ibmcloud cos get-bucket-location --bucket "${bucket_name}" --json |jq .LocationConstraint |tr -d \"; };
list_bucket_contents () { ibmcloud cos list-objects --bucket "${bucket_name}"; };
list_objects_in_bucket () {	ibmcloud cos list-objects --bucket "${bucket_name}" --json |jq .Contents[].Key; };
delete_existing_bucket () { ibmcloud cos delete-bucket --bucket "${bucket_name}" --force --json; };
Get_bucket_headers () { ibmcloud cos head-bucket --bucket "${bucket_name}" --json; };

########################################################################3
get_object_headers () { 
	objectname="${1}";
	ibmcloud cos head-object --bucket "${bucket_name}" --key "${objectname}"
};

########################
upload_object () { #upload an object to a bucket. 
	bucket_name="${1}";
	filepath="${2}";
	mykey="${3}";
	ibmcloud cos put-object --bucket "${bucket_name}" --key "${mykey}" --body "${filepath}" --json #--content-md5 "${md5}"
};

Download_an_object () { #download an object from a bucket
	objectname="${1}";
	ibmcloud cos get-object --bucket "${bucket_name}" --key "${objectname}" --json | jq .
};

###################
check_which_md5 () { 
	if which md5; then
		md5sum="$(which md5) -r" ;
	elif which md5sum; then 
		md5sum="$(which md5sum)" ;
	else echo "no md5sum found.";
		return 1; 
	fi;
};

#################################
generate_md5_for_file () {
	file="${1}";
	$md5sum "${file}" || return 1;
};

split_large_file () {
	largefile="${1}";
	mkdir "${largefile}_tmpdir";
	tmpdir="${largefile}_tmpdir";
	cd "${tmpdir}";
	tmpdir="${PWD}";
	largefile="${largefile##*/}"
	split -a 3 -b 50m "../${largefile}" "${tmpdir}/${largefile}.";
	echo "${tmpdir}";
	cd -
};

check_filesize () {
	filepath="${1}"
	du -m "${filepath}";
};

###################################################
get_files_to_upload () {
	workingdirectory="${1}";
	get_bucket_name; #fills the variable ${bucket_name}"
	if ! [[ -d $workingdirectory ]]; then
		echo "usage:${0} case_directory";
		return 1;
	else
		cd "${workingdirectory}";
		workingdirectory="${PWD}"
		casefile="${workingdirectory##*/}"
		echo "case file is ${casefile}";
	fi
	if  [[ -f "${workingdirectory}/object_name.map" ]]; then 
		echo "object_name.map exist!";
		while IFS=, read -r mydate md5 filepath etag objectkey; do
			get_object_headers "${objectkey}";
		done < "${workingdirectory}/object_name.map";

	fi
};

###################################################
#Create a new multipart upload
create_multipart_upload () {
	#set -x 
	mybucket="${1}";
	mykey="${2}";
	#echo "create multipart upload"
	ibmcloud cos create-multipart-upload --bucket "${bucket_name}" --key "${mykey}" --json | jq .UploadId |tr -d \"
	#set +x
};

abort_multipart_upload () {
	#set -x
	mybucket="${1}"
	mykey="${1}";
	myuploadid="${2}";
	#echo "remove multipart upload"
	
	ibmcloud cos abort-multipart-upload --bucket "${bucket_name}" --key "${mykey}" --upload-id "${myuploadid}" #--json
	#set +x
};
#Complete a multipart upload
complete_multipart_upload () {
	#set -x
	mybucket="${1}";
	mykey="${2}";
	myuploadid="${3}";
	jsonfile="file://${filepartsdir}"/fileparts.tags;
	ibmcloud cos complete-multipart-upload --bucket "${bucket_name}" --key "${mykey}" --upload-id "${myuploadid}" --multipart-upload  "${jsonfile}" --json #[--region REGION] [--json]
	#set +x
};
#List in-progress multipart uploads
list_multipart_uploads () {
	mykey="${1}";
	ibmcloud cos list-multipart-uploads --bucket "${bucket_name}" #[--delimiter DELIMITER] [--encoding-type METHOD] [--prefix PREFIX] [--key-marker value] [--upload-id-marker value] [--page-size SIZE] [--max-items NUMBER] [--region REGION] [--json]
};
#List parts
list_parts () {
	mykey="${1}";
	ibmcloud cos list-parts --bucket "${bucket_name}" --key "${mykey}" --upload-id ID --part-number-marker VALUE #[--page-size SIZE] [--max-items NUMBER] [--region REGION] [--json]
};
#Upload a part
upload_part () {
	mybucket="${1}";
	mykey="${2}";
	myuploadid="${3}";
	partnum="${4}";
	filepath="${5}";

	ibmcloud cos upload-part --bucket "${bucket_name}" --key "${mykey}" --upload-id "${myuploadid}" --part-number "${partnum}" --body "${filepath}" --json |jq .ETag | tr -d \"

};

#--multipart-upload 'Parts=[{ETag=string,PartNumber=integer},{ETag=string,PartNumber=integer}]'
#########################################################
do_upload () {
	#set -x
	workingdirectory="${1}";
	completed="${workingdirectory}/completed/";
	mkdir  "${completed}" ;
	for file in "${workingdirectory}"/*; do
		if [[ -d "${file}" || "${file}" ==  *object_name.map ]]; then
			echo "directory or object_name.map file found: ${file}. skipping!";
			continue;
		fi;
		mydate="$(date +%Y%m%d%H%M%S)";
		read -r md5 filepath <<< $(generate_md5_for_file "${file}");
		objectkey="${casefile}/${md5}";
		read -r filesize _ <<< $(check_filesize "${filepath}"; );

		if [[ "$filesize" -ge 100 ]]; then
			echo "file is greater than 100mb. filesize: ${filesize}mb";
			echo "splitting large file in to 50mb chunks for multipart upload.";
			read filepartsdir <<< $(split_large_file  "${filepath}");
			read -r uploadid <<< $(create_multipart_upload "${bucket_name}" "${objectkey}"; );
			fileparts=(${filepartsdir}/*);
			mkdir "${filepartsdir}/completed"
			printf "%b" "{\n   \"Parts\":[\n" >> "${filepartsdir}"/fileparts.tags;
			for part in "${!fileparts[@]}"; do
				read partmd5 _ <<< $(generate_md5_for_file "${fileparts[$part]}");
				echo "uploading part ${fileparts[$part]}, md5: ${partmd5}";
				read partetag <<< $( upload_part "${bucket_name}" "${objectkey}" "${uploadid}" "$(($part +1))" "${fileparts[$part]}");
				if [[ "${partetag}" != "${partmd5}" ]]; then
					echo "${partetag} ${partmd5} do not match!";
					echo "retrying...";
					read partetag <<< $( upload_part "${bucket_name}" "${objectkey}" "${uploadid}" "$(($part +1))" "${fileparts[$part]}");
					if [[ "${partetag}" != "${partmd5}" ]]; then
						echo "returned md5 still doesnt match. something is wrong.";
						exit 1;
					fi

				else
					echo "upload part md5 matches returned md5. part upload complete.";
					if (( $part +1 <  ${#fileparts[@]} )); then
						printf "%b" "\n      {\n         \"PartNumber\":$(($part +1)),\n         \"ETag\":\"${partetag}\"\n      },\n" >> "${filepartsdir}"/fileparts.tags;
					elif (( $part +1 == ${#fileparts[@]} )) ; then
						printf "%b" "\n      {\n         \"PartNumber\":$(($part +1)),\n         \"ETag\":\"${partetag}\"\n      }\n" >> "${filepartsdir}"/fileparts.tags;
					else 
						echo "something went wrong. part greater than arraysize!";
						exit 1;
					fi
				echo "move part to part tmp completed directory"
				mv "${fileparts[$part]}" "${filepartsdir}/completed/"

				fi
			done
			printf "%b" "   ]\n}" >> "${filepartsdir}"/fileparts.tags; 
			complete_multipart_upload "${bucket_name}" "${objectkey}" "${uploadid}";
			echo "move large file to completed directory";
			mv -f "${filepath}" "${completed}";
			echo "update logfile with largefile";
			echo "${mydate},${md5},${filepath},${etag},${objectkey}" >> "${workingdirectory}"/object_name.map;
			echo "removing temporary directory";
			rm -rf "${filepartsdir}";
		else 
			echo "file is less than 100mb filesize: ${filesize}mb";
			read etag <<< "$(upload_object "${bucket_name}" "${filepath}" "${objectkey}" | jq .ETag | tr -d \")";
			if  [[ "${etag}" != "${md5}" ]]; then
				echo "something went wrong. the md5sums do not match!";
				echo "${md5} not equal to ${etag}";
				return 1;
			else
				echo "${md5} object upload ok. md5sums match.";
			fi;
			echo "updating logfile";
			echo "${mydate},${md5},${filepath},${etag},${objectkey}" >> "${workingdirectory}"/object_name.map;
			echo "moving file to completed directory";
			mv "${filepath}" "${completed}";

		fi;
	done
	echo "upload complete!"
	#list_bucket_contents;
};

##############################################
#target_resource='1579946910c64cf882a6d94a03c0af2d'

do_main () {

	if ! check_which_md5; then 
		return 1;
	fi
	if ! ibmcloud_login; then
		return 1;
	fi
	if ! get_resource_group; then 
		return 1;
	fi
	if ! set_resource_group; then 
		return 1;
	fi
	if ! get_bucket_name; then 
		return 1;
	fi
	if ! get_files_to_upload "${1}"; then
		return 1;
	fi
	if ! do_upload "${1}"; then
		return 1;
	fi
};

do_main "$@"
#cat "${filepartsdir}"/fileparts.tags;

