pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions

Singleton {
    id: root

    property var entriesByFile: ({})

    // Files that hold settings for a page but aren't the page file itself
    // (shared sections reused by both modes).
    readonly property var extraIndexFiles: [
        { id: "hyprland", path: "modules/ii/settings/pages/DisplaysSection.qml" },
        { id: "hyprland", path: "modules/ii/settings/pages/HdrSection.qml", section: "Displays" },
        { id: "desktop", path: "modules/ii/settings/pages/StickersSection.qml" },
        { id: "bar", path: "modules/ii/settings/pages/BarScreensSection.qml" },
        { id: "hyprland", path: "modules/common/widgets/AutostartApps.qml" }
    ]

    readonly property var indexTargets: SettingsPages.pages.concat(root.extraIndexFiles)

    readonly property var labelledTypes: [
        "ConfigSwitch", "ConfigSpinBox", "ConfigTextArea", "ConfigSelectionArray",
        "ConfigComboBox", "ConfigSlider", "ConfigSelectionShapeArray", "ConfigRow",
        "ColorSelectionArray", "ContentSubsection",
        "MaterialTextArea", "HyprOptionSwitch", "HyprOptionSpinBox",
        "HyprOptionSelection", "HyprOptionText"
    ]

    function parsePage(source, initialSection) {
        const typeOpen = /^\s*([A-Z][\w.]*)\s*\{/;
        const labelProp = /^\s*(title|text|placeholderText):\s*Translation\.tr\(\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')\s*\)/;
        const entries = [];
        const stack = [];
        let section = initialSection ?? "";
        let subsection = "";
        for (const line of source.split("\n")) {
            const prop = line.match(labelProp);
            const type = stack.length > 0 ? stack[stack.length - 1] : null;
            // placeholderText is only the label for MaterialTextArea; elsewhere it's a hint
            if (prop && type && (prop[1] !== "placeholderText" || type === "MaterialTextArea")) {
                const label = (prop[2] ?? prop[3]).replace(/\\(["'])/g, "$1");
                if (type === "ContentSection" && prop[1] === "title") {
                    section = label;
                    subsection = "";
                    entries.push({ kind: "section", section: label, subsection: "", label: label });
                } else if (root.labelledTypes.includes(type)) {
                    entries.push({ kind: "option", section: section, subsection: type === "ContentSubsection" ? "" : subsection, label: label });
                    if (type === "ContentSubsection") subsection = label;
                }
            }
            const opens = (line.match(/\{/g) || []).length;
            const closes = (line.match(/\}/g) || []).length;
            for (let i = 0; i < closes; i++) stack.pop();
            const typeMatch = line.match(typeOpen);
            for (let i = 0; i < opens; i++) stack.push(i === 0 && typeMatch ? typeMatch[1] : null);
        }
        return entries;
    }

    function indexFile(path, pageId, source, section) {
        const next = Object.assign({}, root.entriesByFile);
        next[path] = { pageId: pageId, entries: root.parsePage(source, section) };
        root.entriesByFile = next;
    }

    function entriesFor(pageId) {
        const out = [];
        for (const key of Object.keys(root.entriesByFile)) {
            const file = root.entriesByFile[key];
            if (file.pageId === pageId) out.push(...file.entries);
        }
        return out;
    }

    function search(query, limit) {
        const tokens = query.toLowerCase().trim().split(/\s+/).filter(t => t.length > 0);
        if (tokens.length === 0) return [];

        const results = [];
        for (const page of SettingsPages.pages) {
            const pageName = page.name.toLowerCase();
            const pageScore = root.scoreText(pageName, tokens);
            if (pageScore > 0) {
                results.push({
                    pageId: page.id, pageName: page.name, icon: page.icon,
                    kind: "page", section: "", label: page.name, score: pageScore + 50
                });
            }
            for (const entry of root.entriesFor(page.id)) {
                const label = Translation.tr(entry.label);
                const section = Translation.tr(entry.section);
                const haystack = (label + " " + entry.label + " " + section + " " + pageName).toLowerCase();
                if (!tokens.every(t => haystack.includes(t))) continue;
                const labelScore = Math.max(
                    root.scoreText(label.toLowerCase(), tokens),
                    root.scoreText(entry.label.toLowerCase(), tokens)
                );
                results.push({
                    pageId: page.id, pageName: page.name, icon: page.icon,
                    kind: entry.kind, section: section, label: label, rawLabel: entry.label, rawSection: entry.section, subsection: Translation.tr(entry.subsection ?? ""), rawSubsection: entry.subsection ?? "",
                    score: labelScore + (entry.kind === "section" ? 10 : 0)
                });
            }
        }
        results.sort((a, b) => b.score - a.score);
        return results.slice(0, limit);
    }

    function scoreText(text, tokens) {
        let score = 0;
        for (const token of tokens) {
            const at = text.indexOf(token);
            if (at < 0) continue;
            if (text === token) score += 100;
            else if (at === 0) score += 60;
            else if (text[at - 1] === " ") score += 40;
            else score += 20;
        }
        return score;
    }

    Instantiator {
        model: root.indexTargets
        delegate: FileView {
            required property var modelData
            path: FileUtils.trimFileProtocol(Quickshell.shellPath(modelData.path))
            onLoaded: root.indexFile(modelData.path, modelData.id, text(), modelData.section)
        }
    }
}
