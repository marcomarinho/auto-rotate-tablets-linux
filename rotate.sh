#!/bin/sh
# Auto rotate screen based on device orientation
#
# Copyright (c) 2021 Stephan Helma
# Copyright (c) 2016 chadm (https://linuxappfinder.com/blog/auto_screen_rotation_in_ubuntu)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

GDBUS=gdbus
XINPUT=xinput
XRANDR=xrandr

# Receives input from monitor-sensor (part of iio-sensor-proxy package)
# Screen orientation and launcher location is set based upon accelerometer position
# Launcher will be on the left in a landscape orientation and on the bottom in a portrait orientation
# This script should be added to startup applications for the user

# Clear sensor.log so it doesn't get too long over time
> sensor.log

# Launch monitor-sensor and store the output in a variable that can be parsed by the rest of the script
monitor-sensor >> sensor.log 2>&1 &

# Parse output or monitor sensor to get the new orientation whenever the log file is updated
# Possibles are: normal, bottom-up, right-up, left-up
# Light data will be ignored
while inotifywait -e modify sensor.log; do
# Read the last line that was added to the file and get the orientation
CURRENTORIENTATION=$(tail -n 1 sensor.log | grep 'orientation' | grep -oE '[^ ]+$')

# Functions
get_dbus_orientation () {
    # Get the orientation from the DBus
    #
    # No options.

    # DBus to query to get the current orientation
    DBUS="--system --dest net.hadess.SensorProxy --object-path /net/hadess/SensorProxy"

    # Check, if DBus is available
    ORIENTATION=$($GDBUS call $DBUS \
                        --method org.freedesktop.DBus.Properties.Get \
                                 net.hadess.SensorProxy HasAccelerometer)
    if test $? != 0; then
        echo $ORIENTATION
        echo " (Is the 'iio-sensor-proxy' package installed and enabled?)"
        exit 20
    elif test "$ORIENTATION" != "(<true>,)"; then
        echo "No sensor available!"
        echo " (Does the computer has a hardware accelerometer?)"
        exit 21
    fi

    # Get the orientation from the DBus
    ORIENTATION=$($GDBUS call $DBUS \
                        --method org.freedesktop.DBus.Properties.Get \
                        net.hadess.SensorProxy AccelerometerOrientation)

    # Release the DBus
    $GDBUS call --system $DBUS --method net.hadess.SensorProxy.ReleaseAccelerometer > /dev/null

    # Normalize the orientation
    case $ORIENTATION in
        "(<'normal'>,)")
            ORIENTATION=normal
            ;;
        "(<'bottom-up'>,)")
            ORIENTATION=inverted
            ;;
        "(<'left-up'>,)")
            ORIENTATION=left
            ;;
        "(<'right-up'>,)")
            ORIENTATION=right
            ;;
        *)
            echo "Orientation $ORIENTATION unknown!"
            echo " (Known orientations are: normal, bottom-up, left-up and right-up.)"
            exit 22
    esac

    # Return the orientation found
    echo $ORIENTATION
}

do_rotate () {
    # Rotate screen and pointers
    #
    # $1: The requested mode (only "screen" gets a special treatment)
    # $2: The new orientation
    # $3: The screen to rotate
    # $4-: The pointers to rotate

    TRANSFORM='Coordinate Transformation Matrix'

    MODE=$1
    shift

    ORIENTATION=$1
    shift

    # Rotate the screen
    if test $MODE != screen; then
        # Only rotate it, if we have not got the orientation from the screen
        $XRANDR --output $1 --rotate $ORIENTATION
    fi
    shift

    # Rotate all pointers
    while test $# -gt 0; do
        case $ORIENTATION in
            normal)
                $XINPUT set-prop $1 "$TRANSFORM" 1 0 0 0 1 0 0 0 1
                ;;
            inverted)
                $XINPUT set-prop $1 "$TRANSFORM" -1 0 1 0 -1 1 0 0 1
                ;;
            left)
                $XINPUT set-prop $1 "$TRANSFORM" 0 -1 1 1 0 0 0 0 1
                ;;
            right)
                $XINPUT set-prop $1 "$TRANSFORM" 0 1 0 -1 0 1 0 0 1
                ;;
        esac
        shift
    done
}

MODE=auto
# Get the display
XDISPLAY=$($XRANDR --current --verbose | grep primary | cut --delimiter=" " -f1)

# Get the tablet's orientation
case $MODE in
    auto)
        ORIENTATION=$(get_dbus_orientation)
        ret=$?
        if test $ret != 0; then
            echo $ORIENTATION
            echo "(To use this script, supply the orientation normal, inverted, left or right on the command line.)"
            exit $ret
        fi
        ;;
    screen)
        ORIENTATION=$(get_screen_orientation $XDISPLAY)
        ret=$?
        if test $ret != 0; then
            echo $ORIENTATION
            exit $ret
        fi
        ;;
    next)
        ORIENTATION=$(get_screen_orientation $XDISPLAY)
        ret=$?
        if test $ret != 0; then
            echo $ORIENTATION
            exit $ret
        fi
        case $ORIENTATION in
            normal)
                ORIENTATION=left
                ;;
            left)
                ORIENTATION=inverted
                ;;
            inverted)
                ORIENTATION=right
                ;;
            right)
                ORIENTATION=normal
                ;;
            *)
                ORIENTATION=normal
                ;;
        esac
        ;;
    previous)
        ORIENTATION=$(get_screen_orientation $XDISPLAY)
        ret=$?
        if test $ret != 0; then
            echo $ORIENTATION
            exit $ret
        fi
        case $ORIENTATION in
            normal)
                ORIENTATION=right
                ;;
            left)
                ORIENTATION=normal
                ;;
            inverted)
                ORIENTATION=left
                ;;
            right)
                ORIENTATION=inverted
                ;;
            *)
                ORIENTATION=normal
                ;;
        esac
        ;;
    normal|inverted|left|right)
        ORIENTATION=$MODE
        ;;
    *)
        echo "Unknown command line parameter orientation $MODE"
        exit 1
esac

# Get all pointers
POINTERS=$($XINPUT | grep slave | grep pointer | sed -e 's/^.*id=\([[:digit:]]\+\).*$/\1/')

# Set the actions to be taken for each possible orientation
case "$CURRENTORIENTATION" in
normal)
do_rotate $MODE normal $XDISPLAY $POINTERS ;;
bottom-up)
do_rotate $MODE inverted $XDISPLAY $POINTERS ;;
right-up)
do_rotate $MODE right $XDISPLAY $POINTERS ;;
left-up)
do_rotate $MODE left $XDISPLAY $POINTERS ;;
esac
done
