#!/usr/bin/env bash
strings=(
        'bios-vendor'
        'bios-version'
        'bios-release-date'
        'system-manufacturer'
        'system-product-name'
        'system-version'
        'system-serial-number'
        'system-uuid'
        'baseboard-manufacturer'
        'baseboard-product-name'
        'baseboard-version'
        'baseboard-serial-number'
        'baseboard-asset-tag'
        'chassis-manufacturer'
        'chassis-type'
        'chassis-version'
        'chassis-serial-number'
        'chassis-asset-tag'
        'processor-family'
        'processor-manufacturer'
        'processor-version'
        'processor-frequency'
)

for element in "${strings[@]}" ; do
        printf "%s" "${element} is:" 
		dmidecode -s "${element}";
done
