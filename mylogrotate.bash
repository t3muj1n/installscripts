#! /usr/bin/env bash
for file in ./*; do
	if [[ -d $file ]]; then
   	continue;
   fi
   if [[ $file == *.log ]]; then 
      mv -f "${file}" "${file}.0";
   fi

done

filenames=(*.log.?);

read -r numfiles <<< $(echo "${#filenames[@]}");
for (( i=${#filenames[@]} ; i > -1; i--)) ; do
   if [[ ${filenames[i]} == '' ]]; then
      continue;
   else
      read -r name ext num <<< "$( echo ${filenames[i]} | tr '.' ' ')";
      read -r newfilename <<< "$( echo "${name}.${ext}.$((num + 1))" )";
      mv -f "${filenames[i]}" "./$newfilename"

   fi
done

touch access.log
touch error.log
