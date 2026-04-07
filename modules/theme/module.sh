#!/bin/bash

theme::init() {
    :
}

theme::check() {
    return 0
}

theme::preview() {
    echo "Would apply theme configuration..."
}

theme::apply() {
    echo "Applying theme configuration..."
}

theme::status() {
    echo "Theme status ok"
}
