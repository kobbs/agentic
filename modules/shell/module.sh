#!/bin/bash

shell::init() {
    :
}

shell::check() {
    return 0
}

shell::preview() {
    echo "Would apply shell configuration..."
}

shell::apply() {
    echo "Applying shell configuration..."
}

shell::status() {
    echo "Shell status ok"
}
