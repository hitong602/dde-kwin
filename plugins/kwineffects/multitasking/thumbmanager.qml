import QtQuick 2.0
import QtQuick.Window 2.0
import com.deepin.kwin 1.0
import QtGraphicalEffects 1.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.kwin 2.0 as KWin

Rectangle {
    id: root

    color: "transparent"

    x: 0
    y: 0
    width: manager.containerSize.width
    height: manager.containerSize.height

    property int currentDesktop: manager.currentDesktop
    property bool animateLayouting: false

    signal qmlRequestChangeDesktop(int to)
    signal qmlRequestAppendDesktop()
    signal qmlRequestDeleteDesktop(int id)
    signal qmlRequestMove2Desktop(variant wid, int desktop)
    signal qmlRequestSwitchDesktop(int to, int from)

    signal mouseLeaved(); // mouse leaved thumbmanager

    Component.onCompleted: {
        initDesktops();
        animateLayouting = true
    }

    onMouseLeaved: {
        console.log(' !!!------- leaved thumbmanager')
    }

    Component {
        id: desktopItem

        Rectangle {
            id: thumbRoot
            color: "transparent"

            width: manager.thumbSize.width
            height: manager.thumbSize.height
            property int desktop: componentDesktop

            //FIXME: define a enum {
            //    PendingRemove,
            //    PendingSwitch
            //}
            property bool pendingDragRemove: false

            radius: manager.currentDesktop == desktop ? 8 : 6
            //inactive border: solid 1px rgba(0, 0, 0, 0.1);
            //active border: solid 3px rgba(36, 171, 255, 1.0);
            border.width: manager.currentDesktop == desktop ? 3 : 1
            border.color: manager.currentDesktop == desktop ? Qt.rgba(0.14, 0.67, 1.0, 1.0) : Qt.rgba(0, 0, 0, 0.1)

            Drag.keys: ["wsThumb"]
            //NOTE: need to bind to thumbArea.pressed 
            //when mouse pressed and leave DesktopThumbnailManager, drag keeps active 
            //while mouse released or not later.
            Drag.active: thumbArea.pressed && thumbArea.drag.active
            //TOOD: should be cursor position?
            Drag.hotSpot {
                x: width/2
                y: height/2
            }

            states: State {
                when: thumbArea.drag.active
                ParentChange {
                    target: thumbRoot
                    parent: root
                }

                PropertyChanges {
                    target: thumbRoot
                    z: 100
                }
            }

            // make sure dragged ws reset back to Loader's (0, 0)
            Timer {
                id: timerBack
                repeat: false
                interval: 1
                running: false
                onTriggered: {
                    console.log('~~~~~~ restore position')
                    parent.x = 0
                    parent.y = 0
                }
            }

            /* 
             * this is a hack to make a smooth bounce back animation
             * thumbRoot'll be reparnet back to loader and make a sudden visual
             * change of thumbRoot's position. we can disable behavior animation 
             * and set position to the same visual point in the scene (where mouse
             * resides), and then issue the behavior animation.
             */
            property int lastDragX: 0
            property int lastDragY: 0
            property bool disableBehavior: false
            onParentChanged: {
                if (parent != root) {
                    console.log('~~~~~~~ parent chagned to ' + parent)
                    var pos = parent.mapFromGlobal(lastDragX, lastDragY)
                    console.log('----- ' + parent.x + ',' + parent.y + " => " + pos.x + ',' + pos.y)
                    thumbRoot.x = pos.x
                    thumbRoot.y = pos.y
                    disableBehavior = false
                }
            }

            MouseArea {
                id: thumbArea
                anchors.fill: parent
                drag.target: parent
                hoverEnabled: true

                onClicked: {
                    if (close.enabled) {
                        console.log("----------- change to desktop " + thumb.desktop)
                        qmlRequestChangeDesktop(thumb.desktop)
                    }
                }

                onPositionChanged: {
                    // this could happen when mouse press-hold and leave DesktopThumbnailManager
                    if (!thumbArea.pressed && drag.target != null) {
                        drag.target = null
                    }
                }

                onPressed: {
                    //FIXME: make hotSpot follow mouse cursor when drag started
                    // however, this is not accurate, we need a drag-started event
                    thumbRoot.Drag.hotSpot.x = mouse.x
                    thumbRoot.Drag.hotSpot.y = mouse.y

                    drag.target = parent
                }

                onReleased: {
                    // target should be wsDropComponent
                    if (thumbRoot.Drag.target != null) {
                        console.log('------- release ws on ' + thumbRoot.Drag.target)
                        thumbRoot.Drag.drop()
                    }
                    //NOTE: since current the parent is still chagned (by ParentChange), 
                    //delay (x,y) reset into timerBack
                    timerBack.running = true
                    console.log('----- mouse release: ' + parent.x + ',' + parent.y)
                    lastDragX = parent.x
                    lastDragY = parent.y
                    disableBehavior = true
                }

                onEntered: {
                    close.opacity = 1.0
                    close.enabled = true
                }

                onExited: {
                    close.opacity = 0.0
                    close.enabled = false
                }
            }

            // this can accept winthumb type of dropping
            // winthumb is for moving window around desktops
            DropArea {
                id: winDrop
                anchors.fill: parent
                keys: ['winthumb']

                states: State {
                    when: winDrop.containsDrag
                    PropertyChanges {
                        target: thumbRoot
                        border.color: "red"
                    }
                }

                onDropped: {
                    if (drop.keys[0] == 'winthumb') {
                        console.log('~~~~~ Drop winthumb, wid ' + drop.source.wid + ', to desktop ' + desktop
                            + ', from ' + drop.source.owningDesktop.desktop)

                        if (desktop != drop.source.owningDesktop.desktop)
                            qmlRequestMove2Desktop(drop.source.wid, desktop)
                    }
                }

                onEntered: {
                    // source could be DesktopThumbnail or winthumb
                    if (drag.keys[0] == 'winthumb') {
                        console.log('~~~~~  Enter ws ' + desktop + ', wid ' + drag.source.wid
                        + ', keys: ' + drag.keys)
                    } else {
                        drag.accepted = false
                    }

                }
            }

            
            DesktopThumbnail {
                id: thumb
                desktop: thumbRoot.desktop

                anchors.fill: parent
                anchors.margins: manager.currentDesktop == desktop ? 3 : 1
                radius: manager.currentDesktop == desktop ? 8 : 6

                onWindowsLayoutChanged: {
                    for (var i = 0; i < children.length; i++) {
                        if (children[i].objectName == 'repeater')
                            continue;
                        var geo = geometryForWindow(thumb.children[i].wid)
                        thumb.children[i].x = geo.x
                        thumb.children[i].y = geo.y
                        thumb.children[i].width = geo.width
                        thumb.children[i].height = geo.height
                        console.log('  --- relayout ' + desktop + ' ' + geo);
                    }
                }

                Repeater {
                    id: view
                    objectName: 'repeater'

                    model: thumb.windows.length

                    property int cellWidth: 150
                    property int cellHeight: 150

                    delegate: Rectangle {
                        id: viewItem

                        width: view.cellWidth
                        height: view.cellHeight
                        clip: true
                        color: 'transparent'

                        property variant wid: thumb.windows[index]
                        property DesktopThumbnail owningDesktop: thumb

                        PlasmaCore.WindowThumbnail {
                            anchors.fill: parent
                            winId: viewItem.wid
                        }
                        //KWin.ThumbnailItem {
                            //anchors.fill: parent
                            //wId: viewItem.wid
                        //}

                        //NOTE: need to bind to itemArea.pressed
                        //when mouse pressed and leave DesktopThumbnailManager, drag keeps active
                        //while mouse released or not later.
                        Drag.active: itemArea.pressed && itemArea.drag.active
                        Drag.keys: ['winthumb']
                        Drag.hotSpot.x: width/2
                        Drag.hotSpot.y: height/2

                        states: State {
                            when: itemArea.drag.active
                            ParentChange {
                                target: viewItem
                                parent: root
                            }

                            PropertyChanges {
                                target: viewItem
                                z: 100
                            }
                        }

                        // make sure dragged ws reset back to Loader's (0, 0)
                        Timer {
                            id: timerBack
                            repeat: false
                            interval: 1
                            running: false
                            onTriggered: {
                                console.log('~~~~~~ restore winthumb position')

                                var geo = thumb.geometryForWindow(wid)
                                viewItem.x = geo.x
                                viewItem.y = geo.y
                            }
                        }

                        property int lastDragX: 0
                        property int lastDragY: 0
                        property bool disableBehavior: false
                        onParentChanged: {
                            if (parent != root) {
                                var pos = parent.mapFromGlobal(lastDragX, lastDragY)
                                viewItem.x = pos.x
                                viewItem.y = pos.y

                                console.log('~~~~~~~ winthumb parent chagned to ' + parent +
                                    ' at ' + pos.x + ',' + pos.y)
                                disableBehavior = false
                            }
                        }

                        MouseArea {
                            id: itemArea

                            anchors.fill: parent
                            drag.target: parent

                            onPositionChanged: {
                                // this could happen when mouse press-hold and leave DesktopThumbnailManager
                                if (!itemArea.pressed && drag.target != null) {
                                    drag.target = null
                                }
                            }

                            onPressed: {
                                drag.target = parent
                            }

                            onReleased: {
                                console.log('--------- DesktopThumbnail.window released ' + viewItem.wid)
                                if (viewItem.Drag.target != null) {
                                    // target must be a DesktopThumbnail
                                    viewItem.Drag.drop()
                                } 
                                timerBack.running = true
                                lastDragX = parent.x
                                lastDragY = parent.y
                                disableBehavior = true
                            }
                        }
                    } // ~ViewItem
                }
            } // ~DesktopThumbnail

            Rectangle {
                id: close
                z: 3 // at the top
                width: closeImg.width
                height: closeImg.height
                x: parent.width - closeImg.width/2
                y: -height/2
                color: "transparent"
                opacity: 0.0

                Image {
                    id: closeImg
                    source: "qrc:///icons/data/close_normal.svg"
                    sourceSize.width: 48
                    sourceSize.height: 48
                }

                Behavior on opacity {
                    PropertyAnimation { duration: 300; easing.type: Easing.InOutCubic }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        console.log("----------- close desktop " + thumb.desktop)
                        qmlRequestDeleteDesktop(thumb.desktop)
                    }

                    onEntered: {
                        closeImg.source = "qrc:///icons/data/close_hover.svg"
                    }

                    onPressed: {
                        closeImg.source = "qrc:///icons/data/close_press.svg"
                    }

                    onExited: {
                        closeImg.source = "qrc:///icons/data/close_normal.svg"
                    }
                }
            }


            Behavior on x {
                enabled: animateLayouting && !disableBehavior
                PropertyAnimation { duration: 300; easing.type: Easing.Linear }
            }

            Behavior on y {
                enabled: animateLayouting && !disableBehavior
                PropertyAnimation { duration: 300; easing.type: Easing.Linear }
            }

        }
    }

    Component {
        id: wsDropComponent

        DropArea {
            id: wsDrop
            width: manager.thumbSize.width
            height: manager.thumbSize.height
            property int designated: index

            z: 1
            keys: ['wsThumb']

            onDropped: {
                /* NOTE:
                 * during dropping, PropertyChanges is still in effect, which means 
                 * drop.source.parent should not be Loader
                 * and drop.source.z == 100
                 */
                if (drop.keys[0] === 'wsThumb') {
                    var from = drop.source.desktop
                    var to = wsDrop.designated
                    if (wsDrop.designated == drop.source.desktop && drop.source.pendingDragRemove) {
                        //FIXME: could be a delete operation but need more calculation
                        console.log("----------- wsDrop: close desktop " + from)
                        qmlRequestDeleteDesktop(from)
                    } else {
                        if (from == to) {
                            return
                        }
                        console.log("----------- wsDrop: reorder desktop ")

                        thumbs.move(from-1, to-1, 1)
                        qmlRequestSwitchDesktop(to, from)
                        // must update layout right now
                        handleLayoutChanged()
                    }
                }
            }

            onEntered: {
                if (drag.keys[0] === 'wsThumb') {
                    console.log('------[wsDrop]: Enter ' + wsDrop.designated + ' from ' + drag.source
                        + ', keys: ' + drag.keys + ', accept: ' + drag.accepted)
                }
            }

            onExited: {
            }

            onPositionChanged: {
                if (drag.keys[0] === 'wsThumb') {
                    //console.log('------ ' + drag.x + ',' + drag.y)
                    if ( drag.y < 30) {
                        hint.visible = true
                    } else {
                        hint.visible = false
                    }
                    drag.source.pendingDragRemove = hint.visible
                }
            }

            Rectangle {
                id: hint
                visible: false
                anchors.fill: parent
                color: 'lightblue'

                Text {
                    text: "Drag upwards to remove"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.572

                    font.family: "Helvetica"
                    font.pointSize: 14
                    color: Qt.rgba(1, 1, 1, 0.5)
                }

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.lineWidth = 0.5;
                        ctx.strokeStyle = "rgba(255, 255, 255, 0.6)";

                        var POSITION_PERCENT = 0.449;
                        var LINE_START = 0.060;

                        ctx.beginPath();
                        ctx.moveTo(width * LINE_START, height * POSITION_PERCENT);
                        ctx.lineTo(width * (1.0 - 2.0 * LINE_START), height * POSITION_PERCENT);
                        ctx.stroke();
                    }
                }
            }
        }
    }


    // list of wwsDropComponent
    ListModel {
        id: placeHolds
    }

    ListModel {
        id: thumbs
    }


    Rectangle {
        id: plus
        visible: manager.showPlusButton
        enabled: visible
        color: "#33ffffff"

        x: 0
        y: 0
        width: manager.thumbSize.width
        height: manager.thumbSize.height
        radius: 6

        Image {
            z: 1
            id: background
            source: backgroundManager.defaultNewDesktopURI
            anchors.fill: parent

            opacity: 0.0
            Behavior on opacity {
                PropertyAnimation { duration: 200; easing.type: Easing.InOutCubic }
            }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    x: background.x
                    y: background.y
                    width: background.width
                    height: background.height
                    radius: 6
                }
            }
        }

        Canvas {
            z: 2
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d");
                var plus_size = 45.0
                ctx.lineWidth = 2
                ctx.strokeStyle = "rgba(255, 255, 255, 1.0)";

                ctx.beginPath();
                ctx.moveTo((width - plus_size)/2, height/2);
                ctx.lineTo((width + plus_size)/2, height/2);

                ctx.moveTo(width/2, (height - plus_size)/2);
                ctx.lineTo(width/2, (height + plus_size)/2);
                ctx.stroke();
            }
        }

        Behavior on x {
            enabled: animateLayouting
            PropertyAnimation { duration: 300; easing.type: Easing.Linear }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                qmlRequestAppendDesktop()
            }
            onEntered: {
                backgroundManager.shuffleDefaultBackgroundURI()
                background.opacity = 0.6
            }

            onExited: {
                background.opacity = 0.0
            }
        }
    } //~ plus button

    function newDesktop(desktop) {
        var r = manager.calculateDesktopThumbRect(desktop-1);

        var src = 'import QtQuick 2.0; Loader { sourceComponent: desktopItem; ' + 
        'property int componentDesktop: ' + desktop + '}';
        var obj = Qt.createQmlObject(src, root, "dynamicSnippet"); 
        obj.x = r.x
        obj.y = r.y
        obj.z = 2
        thumbs.append({'obj': obj});

        var src2 = 'import QtQuick 2.0; Loader { sourceComponent: wsDropComponent; ' + 
        'property int index: ' + desktop + '}';
        var obj2 = Qt.createQmlObject(src2, root, "dynamicSnippet2"); 
        obj2.x = r.x
        obj2.y = r.y
        obj2.z = 1
        placeHolds.append({'obj': obj2});
    }

    function handleAppendDesktop() {
        var id = manager.desktopCount
        console.log('--------------- handleAppendDesktop ' + manager.desktopCount)

        newDesktop(id)
    }

    function handleDesktopRemoved(id) {
        console.log('--------------- handleDesktopRemoved ' + id)
        for (var i = 0; i < thumbs.count; i++) {
            var d = thumbs.get(i)
            if (d.obj.componentDesktop == id) {
                d.obj.destroy()
                thumbs.remove(i)
                break;
            }
        }

        for (var i = 0; i < placeHolds.count; i++) {
            var d = placeHolds.get(i)
            if (d.obj.index == id) {
                d.obj.destroy()
                placeHolds.remove(i)
                break;
            }
        }
    }


    function debugObject(o) {
        //for (var p in Object.getOwnPropertyNames(o)) {
            //console.log("========= " + o[p]);
        //}

        var keys = Object.keys(o);
        for(var i=0; i<keys.length; i++) {
            var key = keys[i];
            // prints all properties, signals, functions from object
            console.log('======== ' + key + ' : ' + o[key]);
        }
    }

    function handleLayoutChanged() {
        console.log('--------------- layoutChanged')
        var r = manager.calculateDesktopThumbRect(manager.desktopCount);
        plus.x = r.x
        plus.y = r.y

        if (manager.desktopCount < thumbs.count) {
            // this has been handled by handleDesktopRemoved
        }

        for (var i = 0; i < thumbs.count; i++) {
            var r = manager.calculateDesktopThumbRect(i);
            //console.log('   ----- ' + (i+1) + ': ' + thumbs.get(i).obj.x + ',' + thumbs.get(i).obj.y + 
                //'  => ' + r.x + ',' + r.y)
            thumbs.get(i).obj.x = r.x
            thumbs.get(i).obj.y = r.y
            thumbs.get(i).obj.componentDesktop = i+1

            placeHolds.get(i).obj.x = r.x
            placeHolds.get(i).obj.y = r.y
            placeHolds.get(i).obj.index = i+1
        }

        // rearrange thumbs
        if (manager.desktopCount > thumbs.count) {
            handleAppendDesktop();
        }
    }

    function initDesktops() {
        var r = manager.calculateDesktopThumbRect(manager.desktopCount);
        plus.x = r.x
        plus.y = r.y

        for (var i = 1; i <= manager.desktopCount; i++) {
            newDesktop(i)
        }
    }
}
