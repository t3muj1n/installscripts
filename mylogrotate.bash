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

for (( i=${#filenames[@]} ; i >= 0; i--)) ; do
   if [[ ${filenames[i]} == '' ]]; then
      continue;
   else
      IFS='.' read -r name ext num <<< "$( echo ${filenames[i]} )";
      read -r newfilename <<< "$( echo "${name}.${ext}.$((num + 1))" )";
      mv -f "${filenames[i]}" "./$newfilename"

   fi
done

touch access.log
touch error.log

