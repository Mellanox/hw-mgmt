#!/usr/bin/python3
#
# SPDX-FileCopyrightText: NVIDIA CORPORATION & AFFILIATES
# Copyright (c) 2023-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

import os
import argparse
import json
import pickle
import re

HW_MGMT_PATH = "/var/run/hw-management/"


def load_json(json_file):
    # Load JSON file contents
    with open(json_file) as file:
        data = json.load(file)
    return data


def process_BOM_dictionary(dictionary, bom_filename, sku):
    if not sku:
        return dictionary
    alternativies_label_name = f"labels_{sku}_alternativies"
    if alternativies_label_name not in dictionary:
        return dictionary
    alternativies_dict = dictionary[alternativies_label_name]

    labels_dict = dictionary[f"labels_{sku}_rev1_array"]
    labels_scale_dict = dictionary[f"labels_scale_{sku}_rev1_array"]

    try:
        # 1. Load and parse BOM file contents:
        # mp2891 0x66 5 voltmon1 mp2891 0x68 5 voltmon2 adt75 0x4a 7 swb_asic1 ...
        with open(bom_filename, 'r') as bom_file:
            bom_file_data = bom_file.read()
            bom_file_array = bom_file_data.split()

        for i in range(0, len(bom_file_array), 4):
            component_lines = bom_file_array[i:i + 4]

            # example : voltmon1
            component_name = component_lines[3]

            # example : mp2891
            component_type = component_lines[0]

            if component_name in alternativies_dict.keys():
                if component_type not in alternativies_dict[component_name].keys():
                    # Missing definition for component type
                    continue
                comp_attr_dict = alternativies_dict[component_name][component_type]
                for comp_attr, val in comp_attr_dict.items():
                    label_name = f"{component_name}_{comp_attr}"
                    labels_dict[label_name] = val["name"]
                    label_scale = val.get("scale", None)
                    if label_scale:
                        labels_scale_dict[label_name] = label_scale
    except BaseException:
        pass
    return dictionary


def save_dictionary(dictionary, dictionary_file):
    # Save the dictionary to a file using pickle
    with open(dictionary_file, 'wb') as file:
        pickle.dump(dictionary, file)


def load_dictionary(dictionary_file):
    # Load the dictionary from the file
    with open(dictionary_file, 'rb') as file:
        dictionary = pickle.load(file)
    return dictionary


def retrieve_value(dictionary, label, key):
    # Retrieve value for the given key from the dictionary
    if label in dictionary:
        for element in dictionary[label].keys():
            if re.match(element, key):
                return dictionary[label][element]
    return None


def main():
    parser = argparse.ArgumentParser(description='JSON Dictionary')
    parser.add_argument('--json_file', help='Path to JSON file')
    parser.add_argument('--dictionary_file', default='/tmp/sensor_labels_dictionary.pkl', help='Path to dictionary file')
    parser.add_argument('--get_value', action='store_true', help='Retrieve value for a given key')
    parser.add_argument('--label', help='Label section in the json file')
    parser.add_argument('--key', help='Key for value retrieval')
    parser.add_argument('--sku', help='Board SKU number')

    args = parser.parse_args()

    if args.json_file:
        # Load JSON file and store the contents in a dictionary
        data = load_json(args.json_file)
        if args.sku:
            sku = args.sku
        else:
            sku = None
        if os.path.isfile(f"{HW_MGMT_PATH}/config/devtree"):
            data = process_BOM_dictionary(data, f"{HW_MGMT_PATH}/config/devtree", sku)
        save_dictionary(data, args.dictionary_file)
        print("Dictionary created and saved successfully.")

    elif args.get_value and args.label and args.key:
        # Retrieve value for the given key from the dictionary
        dictionary = load_dictionary(args.dictionary_file)
        value = retrieve_value(dictionary, args.label, args.key)
        if value is not None:
            print(f"{value}")
        else:
            print("")

    else:
        parser.print_help()


if __name__ == '__main__':
    main()
