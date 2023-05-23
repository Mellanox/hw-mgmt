#!/usr/bin/python3

import argparse
import json
import pickle
import re

def load_json(json_file):
    # Load JSON file contents
    with open(json_file) as file:
        data = json.load(file)
    return data

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

    args = parser.parse_args()

    if args.json_file:
        # Load JSON file and store the contents in a dictionary
        data = load_json(args.json_file)
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
