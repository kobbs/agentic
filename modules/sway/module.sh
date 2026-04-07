#!/bin/bash

sway::init() {
    :
}

sway::check() {
    return 0
}

sway::preview() {
    echo "Would apply sway configuration..."
}

sway::apply() {
    echo "Applying sway configuration..."
}

sway::status() {
    echo "Sway status ok"
}
