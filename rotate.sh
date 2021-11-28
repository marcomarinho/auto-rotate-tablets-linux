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
