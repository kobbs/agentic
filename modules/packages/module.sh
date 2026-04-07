#!/bin/bash

packages::init() {
    :
}

packages::check() {
    return 0
}

packages::preview() {
    echo "Would apply packages configuration..."
}

packages::apply() {
    echo "Applying packages configuration..."
}

packages::status() {
    echo "Packages status ok"
}
