/*
 * Code to detect whether we are on the main menu
 * by ArEyeses, with some code from ar's lib-tm_UiNav plugin
 */

// util functions from ar
string _ExtractMlNameFromLayer(CGameUILayer@ layer) {
    if (layer is null) return "";
    string page = layer.ManialinkPageUtf8;
    if (page.Length == 0) page = "" + layer.ManialinkPage;
    if (page.Length == 0) return "";
    if (page.Length > 4096) page = page.SubStr(0, 4096);
    int idx = _IndexOfFrom(page, "name=\"", 0);
    if (idx < 0) return "";
    idx += 6;
    int end = _IndexOfFrom(page, "\"", idx);
    if (end < 0 || end <= idx) return "";
    return page.SubStr(idx, end - idx);
}
int _IndexOfFrom(const string &in hay, const string &in needle, int start) {
    if (start < 0) start = 0;
    int hlen = int(hay.Length);
    int nlen = int(needle.Length);
    if (nlen == 0) return (start <= hlen ? start : -1);
    if (start > hlen - nlen) return -1;
    uint first = needle[0];
    int lastStart = hlen - nlen;
    for (int i = start; i <= lastStart; ++i) {
        if (hay[i] != first) continue;
        bool matches = true;
        for (int j = 1; j < nlen; ++j) {
            if (hay[i + j] != needle[j]) {
                matches = false;
                break;
            }
        }
        if (matches) return i;
    }
    return -1;
}

CGameManialinkFrame@ GetLayer_Menu(const string &in layer) {
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    if (app is null || app.MenuManager is null) {
        return null;
    }
    CGameManiaApp@ maniaapp = cast<CGameManiaApp>(app.MenuManager.MenuCustom_CurrentManiaApp);
    if (maniaapp is null) {
        return null;
    }

    int index = -1;
    for (uint i = 0; i < maniaapp.UILayers.Length; i++) {
        if (_ExtractMlNameFromLayer(maniaapp.UILayers[i]) == layer) {
            index = i;
        }
    }
    if (index == -1) {
        print('menu app missing id: ' + layer + ' in: ' + maniaapp.UILayers.Length);
        return null;
    }
    if (maniaapp.UILayers[index].LocalPage is null || maniaapp.UILayers[index].LocalPage.MainFrame is null) {
        print('no mainframe');
        return null;
    }

    return maniaapp.UILayers[index].LocalPage.MainFrame;
}
bool AreLayersLoaded_Menu() {
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    if (app is null || app.MenuManager is null) {
        return false;
    }
    CGameManiaApp@ maniaapp = cast<CGameManiaApp>(app.MenuManager.MenuCustom_CurrentManiaApp);
    if (maniaapp is null) {
        return false;
    }

    if (maniaapp.UILayers.Length < 50) {
        return false;
    }
    return true;
}
