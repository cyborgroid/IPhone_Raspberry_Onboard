// Fits stock Ubuntu to a touchphone: the home screen of the After design, Ubuntu
// Touch's launcher on the left edge and spread on the right edge. Everything is
// reversible, so connecting a monitor returns to unmodified Ubuntu and open apps
// keep running through the switch.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const STYLE_CLASS = 'cyborgroid-touch';
const DOCK_UUID = 'ubuntu-dock@ubuntu.com';
const WALLPAPER = 'file:///usr/share/backgrounds/cyborgroid-touch.png';

// [schema, key, value in touch mode]. The previous values are saved and restored.
const TOUCH_SETTINGS = [
    ['org.gnome.desktop.interface', 'color-scheme', 'prefer-dark'],
    ['org.gnome.desktop.interface', 'accent-color', 'orange'],
    ['org.gnome.desktop.interface', 'icon-theme', 'Yaru-dark'],
    ['org.gnome.desktop.background', 'picture-uri', WALLPAPER],
    ['org.gnome.desktop.background', 'picture-uri-dark', WALLPAPER],
    ['org.gnome.desktop.background', 'picture-options', 'zoom'],
    ['org.gnome.desktop.a11y.applications', 'screen-keyboard-enabled', true],
    ['org.gnome.desktop.wm.preferences', 'num-workspaces', 1],
    ['org.gnome.mutter', 'dynamic-workspaces', false],
    ['org.gnome.shell.extensions.dash-to-dock', 'dock-position', 'LEFT'],
    ['org.gnome.shell.extensions.dash-to-dock', 'dock-fixed', false],
    ['org.gnome.shell.extensions.dash-to-dock', 'intellihide', false],
    ['org.gnome.shell.extensions.dash-to-dock', 'autohide', true],
    ['org.gnome.shell.extensions.dash-to-dock', 'extend-height', true],
    ['org.gnome.shell.extensions.dash-to-dock', 'show-apps-at-top', true],
    ['org.gnome.shell.extensions.dash-to-dock', 'dash-max-icon-size', 44],
    ['org.gnome.shell.extensions.dash-to-dock', 'show-trash', false],
    ['org.gnome.shell.extensions.dash-to-dock', 'show-mounts', false],
    ['org.gnome.shell.extensions.dash-to-dock', 'disable-overview-on-startup', true],
    ['org.gnome.shell.extensions.ding', 'show-home', false],
    ['org.gnome.shell.extensions.ding', 'show-trash', false],
    ['org.gnome.shell.extensions.ding', 'show-volumes', false],
];

// Tile grid of the After design. apps: desktop IDs, first one installed wins.
const TILES = [
    [
        {label: '전화', color: '#2fa84f', icon: 'call-start-symbolic', apps: ['org.gnome.Calls.desktop']},
        {label: '메모', color: '#3b62b5', icon: 'accessories-text-editor-symbolic', apps: ['org.gnome.TextEditor.desktop', 'org.gnome.gedit.desktop']},
    ],
    [
        {label: '사진', color: '#7f7088', icon: 'image-x-generic-symbolic', apps: ['org.gnome.Loupe.desktop', 'org.gnome.eog.desktop']},
        {label: '브라우저', color: '#ffffff', asset: 'browser.svg', apps: ['firefox_firefox.desktop', 'firefox.desktop']},
        {label: '파일', color: '#3d78c9', icon: 'folder-symbolic', apps: ['org.gnome.Nautilus.desktop']},
        {label: '문서', color: '#3a9cc7', icon: 'folder-documents-symbolic', apps: ['org.gnome.Papers.desktop', 'org.gnome.Evince.desktop']},
    ],
    [
        {label: '동영상', color: '#5a46a8', icon: 'video-x-generic-symbolic', apps: ['org.gnome.Showtime.desktop', 'org.gnome.Totem.desktop']},
        {label: '앱 센터', color: '#4b4f52', icon: 'system-software-install-symbolic', apps: ['snap-store_snap-store.desktop', 'org.gnome.Software.desktop']},
        {label: '네트워크', color: '#4e5868', icon: 'network-wireless-symbolic', settingsPanel: 'wifi'},
        {label: '설정', color: '#56595c', icon: 'preferences-system-symbolic', apps: ['org.gnome.Settings.desktop']},
    ],
    [
        {label: '터미널', color: '#4a4d50', icon: 'utilities-terminal-symbolic', apps: ['org.gnome.Ptyxis.desktop', 'org.gnome.Terminal.desktop']},
        {label: '시계', color: '#5e6672', icon: 'preferences-system-time-symbolic', apps: ['org.gnome.clocks.desktop']},
        {label: '토큰', color: '#f2f2f2', asset: 'token.svg', apps: ['cyborgroid.desktop']},
        {label: 'Ubuntu', color: '#d9552b', icon: 'start-here-symbolic', action: 'all-apps'},
    ],
];

// Proportions measured on the After design, whose screen is 933 x 1400.
const DESIGN_WIDTH = 933;
const scaleOf = (width, value) => Math.round(value * width / DESIGN_WIDTH);

const UPowerProxy = Gio.DBusProxy.makeProxyWrapper(`<node>
  <interface name="org.freedesktop.UPower.Device">
    <property name="IsPresent" type="b" access="read"/>
    <property name="Percentage" type="d" access="read"/>
    <property name="State" type="u" access="read"/>
  </interface>
</node>`);
const UPOWER_CHARGING = 1;
const UPOWER_FULL = 4;

class HomeScreen {
    constructor(extension) {
        this._extension = extension;
        this._batteryProxy = null;
        this._batterySignal = 0;
        this.actor = new St.Widget({
            name: 'cyborgroidHome',
            layout_manager: new Clutter.BinLayout(),
            reactive: false,
        });
        Main.layoutManager._backgroundGroup.add_child(this.actor);
        this.rebuild();

        this._batteryProxy = new UPowerProxy(Gio.DBus.system, 'org.freedesktop.UPower',
            '/org/freedesktop/UPower/devices/DisplayDevice',
            (proxy, error) => {
                if (!error)
                    this._updateBatteryFromProxy();
            });
        this._batterySignal = this._batteryProxy.connect('g-properties-changed',
            () => this._updateBatteryFromProxy());
    }

    destroy() {
        if (this._batterySignal)
            this._batteryProxy.disconnect(this._batterySignal);
        this.actor.destroy();
    }

    rebuild() {
        this.actor.destroy_all_children();
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor)
            return;
        const {width, height} = monitor;
        this.actor.set_position(monitor.x, monitor.y);
        this.actor.set_size(width, height);
        // Keep above the wallpaper actor, which is recreated when the monitor changes.
        Main.layoutManager._backgroundGroup.set_child_above_sibling(this.actor, null);

        const column = new St.BoxLayout({
            orientation: Clutter.Orientation.VERTICAL,
            x_expand: true,
            y_expand: true,
            style: `padding-top: ${Main.panel.height + scaleOf(width, 58)}px;`,
        });
        this.actor.add_child(column);

        TILES.forEach((row, index) => column.add_child(this._buildRow(row, index, width)));
        column.add_child(new St.Widget({y_expand: true}));
        column.add_child(this._buildDots(width));
        column.add_child(this._buildFingerprint(width));
        this._updateBatteryFromProxy();
    }

    _buildRow(tiles, index, width) {
        const row = new St.BoxLayout({
            x_expand: true,
            style: `padding: 0 ${scaleOf(width, 22)}px; margin-bottom: ${scaleOf(width, 26)}px;`,
        });
        tiles.forEach(tile => row.add_child(this._buildTile(tile, width)));
        if (index === 0)
            row.add_child(this._buildBattery(width));
        return row;
    }

    _buildTile(tile, width) {
        const size = scaleOf(width, 130);
        const glyph = scaleOf(width, 74);
        const app = this._findApp(tile);
        const available = app || tile.action || tile.settingsPanel;

        const button = new St.Button({
            style_class: 'cyborgroid-home-button',
            x_expand: true,
            reactive: Boolean(available),
            can_focus: true,
            opacity: available ? 255 : 110,
        });
        const box = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_align: Clutter.ActorAlign.CENTER});
        button.set_child(box);

        const face = new St.Bin({
            style_class: 'cyborgroid-home-tile',
            style: `background-color: ${tile.color}; width: ${size}px; height: ${size}px; border-radius: ${Math.round(size * 0.22)}px;`,
            x_align: Clutter.ActorAlign.CENTER,
        });
        const gicon = tile.asset
            ? Gio.FileIcon.new(this._extension.dir.get_child('assets').get_child(tile.asset))
            : Gio.ThemedIcon.new(tile.icon);
        face.set_child(new St.Icon({
            gicon,
            icon_size: tile.asset ? scaleOf(width, 104) : glyph,
            style: 'color: #ffffff;',
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
        }));
        box.add_child(face);

        box.add_child(new St.Label({
            text: tile.label,
            style_class: 'cyborgroid-home-label',
            style: `font-size: ${scaleOf(width, 30)}px; margin-top: ${scaleOf(width, 8)}px;`,
            x_align: Clutter.ActorAlign.CENTER,
        }));

        if (available)
            button.connect('clicked', () => this._activate(tile, app));
        return button;
    }

    _findApp(tile) {
        const system = Shell.AppSystem.get_default();
        for (const id of tile.apps ?? []) {
            const app = system.lookup_app(id);
            if (app)
                return app;
        }
        return null;
    }

    _activate(tile, app) {
        if (tile.action === 'all-apps') {
            Main.overview.showApps();
        } else if (tile.settingsPanel) {
            GLib.spawn_command_line_async(`gnome-control-center ${tile.settingsPanel}`);
        } else {
            app.activate();
        }
    }

    _buildBattery(width) {
        // Spans the last two columns of the first row.
        const box = new St.BoxLayout({
            orientation: Clutter.Orientation.VERTICAL,
            x_expand: true,
            y_align: Clutter.ActorAlign.START,
            style: `padding: ${scaleOf(width, 4)}px ${scaleOf(width, 16)}px 0 ${scaleOf(width, 28)}px;`,
        });
        // Claims the width of two tiles, so the first two columns stay on the grid.
        box.set_width(scaleOf(width, 445));
        box.x_expand = false;

        const line = new St.BoxLayout({y_align: Clutter.ActorAlign.CENTER});
        this._bolt = new St.Icon({
            icon_name: 'battery-level-100-charging-symbolic',
            icon_size: scaleOf(width, 72),
            style_class: 'cyborgroid-home-bolt',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._percent = new St.Label({
            text: '--',
            style_class: 'cyborgroid-home-percent',
            style: `font-size: ${scaleOf(width, 104)}px; margin-left: ${scaleOf(width, 14)}px;`,
            y_align: Clutter.ActorAlign.CENTER,
        });
        line.add_child(this._bolt);
        line.add_child(this._percent);
        box.add_child(line);

        this._barWidth = scaleOf(width, 390);
        const barHeight = scaleOf(width, 18);
        const track = new St.Widget({
            style_class: 'cyborgroid-home-bar-track',
            width: this._barWidth,
            height: barHeight,
            style: `margin-top: ${scaleOf(width, 12)}px;`,
        });
        this._barFill = new St.Widget({style_class: 'cyborgroid-home-bar-fill', width: 0, height: barHeight});
        track.add_child(this._barFill);
        box.add_child(track);
        return box;
    }

    _updateBatteryFromProxy() {
        const proxy = this._batteryProxy;
        const present = proxy?.IsPresent === true;
        const state = proxy?.State;
        this.setBattery(present ? proxy.Percentage : null, state === UPOWER_CHARGING || state === UPOWER_FULL);
    }

    // With no battery gauge this shows "--" rather than a made-up number.
    setBattery(percent, charging) {
        if (!this._percent)
            return;
        const known = percent !== null && percent !== undefined;
        this._percent.text = known ? `${Math.round(percent)}%` : '--';
        this._barFill.width = known ? Math.round(this._barWidth * percent / 100) : 0;
        this._bolt.opacity = charging ? 255 : 0;
    }

    _buildDots(width) {
        const box = new St.BoxLayout({
            x_align: Clutter.ActorAlign.CENTER,
            style: `spacing: ${scaleOf(width, 18)}px; margin-bottom: ${scaleOf(width, 24)}px;`,
        });
        for (let i = 0; i < 3; i++) {
            const size = scaleOf(width, 16);
            box.add_child(new St.Widget({
                style_class: i === 0 ? 'cyborgroid-home-dot cyborgroid-home-dot-active' : 'cyborgroid-home-dot',
                width: size,
                height: size,
            }));
        }
        return box;
    }

    _buildFingerprint(width) {
        // The device has no fingerprint sensor: this is the design's button, and it locks.
        const button = new St.Button({
            x_align: Clutter.ActorAlign.CENTER,
            style: `margin-bottom: ${scaleOf(width, 72)}px;`,
            can_focus: true,
        });
        button.set_child(new St.Icon({
            gicon: Gio.FileIcon.new(this._extension.dir.get_child('assets').get_child('fingerprint.svg')),
            icon_size: scaleOf(width, 132),
        }));
        button.connect('clicked', () => Main.screenShield?.lock(true));
        return button;
    }
}

export default class CyborgroidTouchExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._touch = false;
        this._gestures = [];
        this._signals = [];

        const monitors = global.backend.get_monitor_manager();
        this._connect(monitors, 'monitors-changed', () => this._sync());
        this._connect(this._settings, 'changed::mode-override', () => this._sync());
        this._sync();
    }

    disable() {
        this._leaveTouch();
        for (const [object, id] of this._signals)
            object.disconnect(id);
        this._signals = [];
        this._settings = null;
    }

    _connect(object, signal, callback) {
        this._signals.push([object, object.connect(signal, callback)]);
    }

    _wantsTouch() {
        const override = this._settings.get_string('mode-override');
        if (override !== 'auto')
            return override === 'touch';
        const monitors = global.backend.get_monitor_manager().get_monitors();
        return !monitors.some(monitor => /^(HDMI|DP)/.test(monitor.get_connector()));
    }

    _sync() {
        const touch = this._wantsTouch();
        if (touch && !this._touch)
            this._enterTouch();
        else if (!touch && this._touch)
            this._leaveTouch();
        else if (touch)
            this._home.rebuild();
    }

    _enterTouch() {
        this._touch = true;
        this._applySettings();
        Main.layoutManager.uiGroup.add_style_class_name(STYLE_CLASS);

        // Ubuntu Touch's status row: the clock moves right, Activities goes away.
        this._dateMenu = Main.panel.statusArea.dateMenu.container;
        this._dateMenuParent = this._dateMenu.get_parent();
        this._dateMenuParent.remove_child(this._dateMenu);
        Main.panel._leftBox.insert_child_at_index(this._dateMenu, 0);
        Main.panel.statusArea.activities?.container.hide();

        this._home = new HomeScreen(this);
        this._addEdgeGesture(St.Side.LEFT, () => this._showLauncher());
        this._addEdgeGesture(St.Side.RIGHT, () => Main.overview.show());
        this._addEdgeGesture(St.Side.TOP, () => Main.panel.statusArea.quickSettings.menu.open());

        this._windowSignal = global.display.connect('window-created',
            (_display, window) => this._fitToScreen(window));
        for (const actor of global.get_window_actors())
            this._fitToScreen(actor.meta_window);
    }

    _leaveTouch() {
        if (!this._touch)
            return;
        this._touch = false;
        global.display.disconnect(this._windowSignal);
        for (const gesture of this._gestures)
            global.stage.remove_action(gesture);
        this._gestures = [];

        this._home.destroy();
        this._home = null;

        Main.panel._leftBox.remove_child(this._dateMenu);
        this._dateMenuParent.add_child(this._dateMenu);
        Main.panel.statusArea.activities?.container.show();

        Main.layoutManager.uiGroup.remove_style_class_name(STYLE_CLASS);
        this._restoreSettings();
    }

    _addEdgeGesture(side, callback) {
        const gesture = new Shell.EdgeDragGesture({name: `Cyborgroid edge ${side}`, side});
        gesture.connect('may-recognize', () => Main.actionMode === Shell.ActionMode.NORMAL);
        gesture.connect('end', callback);
        global.stage.add_action(gesture);
        this._gestures.push(gesture);
    }

    // The dock is Ubuntu's own, revealed by the edge swipe as Ubuntu Touch's launcher is.
    _showLauncher() {
        Main.extensionManager.lookup(DOCK_UUID)?.stateObj?.dockManager?.mainDock?._show();
    }

    // Apps fill the screen, as on a phone. Windows too big for it are left to the
    // window manager rather than forced, so any Ubuntu app stays usable.
    _fitToScreen(window) {
        if (window.get_window_type() !== Meta.WindowType.NORMAL)
            return;
        GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            if (window.can_maximize())
                window.maximize();
            return GLib.SOURCE_REMOVE;
        });
    }

    _schema(id) {
        const found = Gio.SettingsSchemaSource.get_default().lookup(id, true);
        return found ? new Gio.Settings({settings_schema: found}) : null;
    }

    _applySettings() {
        const saved = this._settings.get_value('desktop-settings').deepUnpack();
        const first = Object.keys(saved).length === 0;
        for (const [schema, key, value] of TOUCH_SETTINGS) {
            const settings = this._schema(schema);
            if (!settings)
                continue;
            const current = settings.get_value(key);
            // A crash in touch mode must not overwrite the real settings with touch ones.
            if (first)
                saved[`${schema}:${key}`] = current.print(true);
            settings.set_value(key, new GLib.Variant(current.get_type_string(), value));
        }
        if (first)
            this._settings.set_value('desktop-settings', new GLib.Variant('a{ss}', saved));
    }

    _restoreSettings() {
        const saved = this._settings.get_value('desktop-settings').deepUnpack();
        for (const [name, printed] of Object.entries(saved)) {
            const [schema, key] = name.split(':');
            this._schema(schema)?.set_value(key, GLib.Variant.parse(null, printed, null, null));
        }
        this._settings.reset('desktop-settings');
    }
}
