namespace NextCampaign {
    const string CACHE_FILE = IO::FromStorageFolder("next_campaign_cache.json");
    bool mainMenuVisible = false;
    Json::Value cache;
    bool cacheDirty = false;

    string nextCampaignName = "";
    uint nextCampaignTimestamp = 0;
    string currentCampaign = "";
    array<string> seasons = { "Winter", "Spring", "Summer", "Fall" };

    uint lastFetchAttempt = 0;
    UI::Font@ fontMontserratBold = UI::LoadFont("Montserrat-Bold.ttf");

    // ===== INIT =====

    void Main() {
        LoadCache();
        startnew(UpdateLoop);
        while (!AreLayersLoaded_Menu()) {
            sleep(1000);
        }
        while (true) {
            sleep(1000);
            if (GetApp().RootMap is null) {
                mainMenuVisible = GetLayer_Menu('Page_HomePage').Visible;
            }
            else {
                mainMenuVisible = false;
            }
        }
    }

    void LoadCache() {
        if (IO::FileExists(CACHE_FILE)) {
            try {
                cache = Json::FromFile(CACHE_FILE);
            } catch {
                cache = Json::Object();
            }
        } else {
            cache = Json::Object();
        }

        ApplyCache();
    }

    void SaveCache() {
        if (!cacheDirty) return;
        Json::ToFile(CACHE_FILE, cache, true);
        cacheDirty = false;
    }

    void ApplyCache() {
        if (cache.HasKey("nextCampaignName"))
            nextCampaignName = cache["nextCampaignName"];

        if (cache.HasKey("nextCampaignTimestamp"))
            nextCampaignTimestamp = cache["nextCampaignTimestamp"];

        if (cache.HasKey("currentCampaign"))
            currentCampaign = cache["currentCampaign"];
    }

    // ===== UPDATE LOOP =====

    void UpdateLoop() {
        while (true) {
            TryFetch();
            sleep(60000); // check once per minute
        }
    }

    void TryFetch() {
        // simple anti spam guard
        if (Time::Stamp - lastFetchAttempt < 30) return;
        lastFetchAttempt = Time::Stamp;

        Net::HttpRequest@ req = Net::HttpGet("https://nextcampaign.m8.no/campaign_info.json");

        uint start = Time::Stamp;
        while (!req.Finished() && Time::Stamp - start < 15)
            yield();

        if (!req.Finished() || req.ResponseCode() != 200)
            return;

        auto responseJson = req.Json();

        if (!responseJson.HasKey("currentCampaign") || !responseJson.HasKey("endTimestamp"))
            return;

        string current = responseJson["currentCampaign"];
        currentCampaign = current;
        nextCampaignName = NextSeason(current);
        nextCampaignTimestamp = uint(responseJson["endTimestamp"]);

        cache["currentCampaign"] = currentCampaign;
        cache["nextCampaignName"] = nextCampaignName;
        cache["nextCampaignTimestamp"] = nextCampaignTimestamp;

        if (responseJson.HasKey("nextRequestInSeconds")) {
            cache["nextFetchAfter"] = Time::Stamp + uint(responseJson["nextRequestInSeconds"]);
        }

        cacheDirty = true;
        SaveCache();
    }

    // ===== SEASON LOGIC =====

    string NextSeason(const string&in current) {
        auto parts = current.Split(" ");
        if (parts.Length != 2) return "";

        string season = parts[0];
        int year = Text::ParseInt(parts[1]);

        int idx = seasons.Find(season);
        if (idx < 0) return "";

        int nextIdx = (idx + 1) % seasons.Length;

        if (season == "Fall")
            year += 1;

        return seasons[nextIdx] + " " + year;
    }

    int GetQuarterFromSeason(const string&in season) {
        int idx = seasons.Find(season);
        if (idx < 0) return 0;
        return idx + 1;
    }

    int quartersSinceSummer2020(int year, int quarter) {
        int startYear = 2020;
        int startQuarter = 2; // June 1, 2020 is in Q2
        
        int yearDifference = year - startYear;
        int totalQuarters = yearDifference * 4 + (quarter - startQuarter);
        return totalQuarters;
    }

    int seasonOrdinalSinceSummer2020(int year, int quarter) {
        int seasonIndex = quarter - 1;
        
        array<int> firstYearBySeason = { 2021, 2021, 2020, 2020 };
        if (seasonIndex < 0 || seasonIndex > 3) return 0;
        
        return year - firstYearBySeason[seasonIndex] + 1;
    }

    string toOrdinalNumber(int value) {
        int mod100 = value % 100;
        int mod10 = value % 10;
        
        if (mod100 >= 11 && mod100 <= 13) {
            return value + "th";
        }
        
        if (mod10 == 1) {
            return value + "st";
        } else if (mod10 == 2) {
            return value + "nd";
        } else if (mod10 == 3) {
            return value + "rd";
        }
        
        return value + "th";
    }

    // ===== COUNTDOWN =====

    int GetDaysInMonth(int month, int year) {
        if (month == 2) {
            if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) return 29;
            return 28;
        }
        if (month == 4 || month == 6 || month == 9 || month == 11) return 30;
        return 31;
    }

    string GetCountdown() {
        if (nextCampaignTimestamp == 0)
            return "No data";

        uint64 nowStamp = Time::Stamp;
        uint64 targetStamp = uint64(nextCampaignTimestamp);

        if (nowStamp >= targetStamp)
            return "Live!";

        auto now = Time::Parse(int64(nowStamp));
        auto target = Time::Parse(int64(targetStamp));

        int months = int(target.Month) - int(now.Month);
        if (target.Year > now.Year) months += (int(target.Year) - int(now.Year)) * 12;
        
        int days = int(target.Day) - int(now.Day);
        int hours = int(target.Hour) - int(now.Hour);
        int mins = int(target.Minute) - int(now.Minute);

        if (mins < 0) { mins += 60; hours--; }
        if (hours < 0) { hours += 24; days--; }
        if (days < 0) {
            int prevMonth = int(target.Month) - 1;
            int prevYear = int(target.Year);
            if (prevMonth == 0) { prevMonth = 12; prevYear--; }
            days += GetDaysInMonth(prevMonth, prevYear);
            months--;
        }

        string res = "";
        if (months > 0) {
            res += months + "mo ";
        }
        if (days > 0 || months > 0) {
            res += days + "d ";
        }
        if (hours > 0 || days > 0 || months > 0) {
            res += Text::Format("%02d", hours) + "h ";
            res += Text::Format("%02d", mins) + "m";
        }

        return res;
    }

    void DrawCountdownDigit(int value, const string&in label, float width = 60.0f, bool leadingZero = true) {
        UI::BeginGroup();
        
        // Number
        string valStr = (leadingZero && value < 10 ? "0" : "") + value;
        UI::PushFontSize(32);
        vec2 textSize = UI::MeasureString(valStr);
        UI::SetCursorPosX(UI::GetCursorPos().x + (width - textSize.x) / 2.0f);
        UI::Text(valStr);
        UI::PopFont();
        
        // Label
        UI::PushFontSize(13);
        textSize = UI::MeasureString(label);
        UI::SetCursorPosX(UI::GetCursorPos().x + (width - textSize.x) / 2.0f);
        UI::Text("\\$bbb" + label);
        UI::PopFont();
        
        UI::Dummy(vec2(0, 1));
        UI::EndGroup();
    }

    void Render() {
        //most of the UI checks here come from NaNInf's ChampionMedals via MedalsInMenu
        auto app = cast<CTrackMania@>(GetApp());
        if (!sEnabled) return;
        if (sHideWithOP && !UI::IsOverlayShown()) return;
        if (!mainMenuVisible) {
            return;
        }

        if (app.RootMap !is null || app.CurrentPlayground !is null)
            return;

        if (nextCampaignTimestamp == 0)
            return;

        float width = 38.0f; // Fixed width for each column /* 60.0f */

        uint64 nowStamp = Time::Stamp;
        uint64 targetStamp = uint64(nextCampaignTimestamp);

        auto now = Time::Parse(int64(nowStamp));
        auto target = Time::Parse(int64(targetStamp));

        int months = int(target.Month) - int(now.Month);

        if (target.Year > now.Year) months += (int(target.Year) - int(now.Year)) * 12;
        
        int days = int(target.Day) - int(now.Day);
        int hours = int(target.Hour) - int(now.Hour);
        int mins = int(target.Minute) - int(now.Minute);
        int secs = int(target.Second) - int(now.Second);

        if (secs < 0) { secs += 60; mins--; }
        if (mins < 0) { mins += 60; hours--; }
        if (hours < 0) { hours += 24; days--; }
        if (days < 0) {
            int prevMonth = int(target.Month) - 1;
            int prevYear = int(target.Year);
            if (prevMonth == 0) { prevMonth = 12; prevYear--; }
            days += GetDaysInMonth(prevMonth, prevYear);
            months--;
        }

        string releaseDate = "\\$fff" + Time::FormatString("%a,%e %B %Y at %H:%M", int64(nextCampaignTimestamp));

        UI::PushStyleColor(UI::Col::WindowBg, vec4(0.4f, 0.2f, 0.6f, 0.9f));
        int flags = UI::WindowFlags::NoResize | UI::WindowFlags::NoScrollbar | UI::WindowFlags::AlwaysAutoResize;
        if (!sShowTitlebar) flags |= UI::WindowFlags::NoTitleBar;
        UI::Begin("NextCampaign™", flags);
        if (!sShowTitlebar) {
            UI::PushFont(fontMontserratBold, 25);
            //UI::Text("\\$9feNextCampaign\\$a7f™");
            //UI::Text("\\$s\\$9FEN\\$9EEex\\$9DEt\\$9CECa\\$ABFm\\$AAFpa\\$A9Fi\\$A8Fgn\\$A7F™");
            UI::Text("\\$s\\$A7FN\\$A8Fex\\$A9Ft\\$AAFCa\\$ABFm\\$9CEpa\\$9DEi\\$9EEgn\\$9FE™");
            UI::PopFont();
        }
        if (currentCampaign != "") {
            auto parts = currentCampaign.Split(" ");
            if (parts.Length == 2) {
                string season = parts[0];
                int year = Text::ParseInt(parts[1]);
                int quarter = GetQuarterFromSeason(season);
                if (quarter > 0) {
                    int seasonOrdinal = seasonOrdinalSinceSummer2020(year, quarter);
                    int overallOrdinal = quartersSinceSummer2020(year, quarter);
                    UI::Text("\\$fffThe current campaign is the");
                    UI::Text("\\$fff" + toOrdinalNumber(seasonOrdinal) + " " + season.ToLower() + " campaign, and");
                    UI::Text("\\$fffthe " + toOrdinalNumber(overallOrdinal) + " campaign overall");
                    UI::Text("\\$fffsince Summer 2020");
                }
            }
        }

        if (UI::BeginTable("campaigns_info", 2)) {
            // Row 1: Headers
            UI::TableNextColumn();
            UI::PushFont(UI::Font::DefaultBold, 20);
            UI::Text("\\$s\\$CCCCurrent");
            UI::PopFont();

            UI::TableNextColumn();
            UI::PushFont(UI::Font::DefaultBold, 20);
            UI::Text("\\$s\\$CCCNext");
            UI::PopFont();

            // Row 2: Values
            UI::TableNextColumn();
            UI::Text(currentCampaign);

            UI::TableNextColumn();
            UI::Text(nextCampaignName);

            UI::EndTable();
        }
        UI::PushFont(UI::Font::DefaultBold, 20);
        UI::Text("\\$s\\$CCCNew season");
        UI::PopFont();
        bool showSecs = (months == 0 && days == 0);
        bool showDays = !showSecs;
        // cols: months?, days/secs, hours, mins, secs?
        int cols = (months > 0 ? 1 : 0) + (showDays ? 1 : 0) + 2 + (showSecs ? 1 : 0);
        if (cols <= 3) {
            width = 50.0f;
        }
        UI::PushStyleColor(UI::Col::TableBorderLight, vec4(0.8f, 0.8f, 0.8f, 1.0f));
        UI::PushStyleColor(UI::Col::TableBorderStrong, vec4(0.8f, 0.8f, 0.8f, 1.0f));
        if (UI::BeginTable("countdown", cols, UI::TableFlags::BordersInnerV | UI::TableFlags::BordersOuterH | UI::TableFlags::BordersOuterV)) {
            if (months > 0) {
                UI::TableSetupColumn("mo", UI::TableColumnFlags::WidthFixed, width);
            }
            if (showDays) {
                UI::TableSetupColumn("d", UI::TableColumnFlags::WidthFixed, width);
            }
            UI::TableSetupColumn("h", UI::TableColumnFlags::WidthFixed, width);
            UI::TableSetupColumn("m", UI::TableColumnFlags::WidthFixed, width);
            if (showSecs) {
                UI::TableSetupColumn("s", UI::TableColumnFlags::WidthFixed, width);
            }

            if (months > 0) {
                UI::TableNextColumn();
                DrawCountdownDigit(months, "month"+(months!=1?"s":""), width, false);
            }
            if (showDays) {
                UI::TableNextColumn();
                DrawCountdownDigit(days, "day"+(days!=1?"s":""), width, false);
            }
            UI::TableNextColumn();
            DrawCountdownDigit(hours, "hour"+(hours!=1?"s":""), width);
            UI::TableNextColumn();
            DrawCountdownDigit(mins, "minute"+(mins!=1?"s":""), width);
            if (showSecs) {
                UI::TableNextColumn();
                DrawCountdownDigit(secs, "second"+(secs!=1?"s":""), width);
            }
            UI::EndTable();
        }
        UI::PopStyleColor(2);
        UI::PushFont(UI::Font::DefaultBold, 20);
        UI::Text("\\$s\\$CCCRelease date"); //fa0
        UI::PopFont();
        UI::Text(releaseDate);
        
        //UI::Text("\\$a7fWeb:");
        //UI::SameLine();
        if (UI::Selectable("\\$a7fnextcampaign.m8.no", false)) {
            OpenBrowserURL("https://nextcampaign.m8.no/");
        }
        
        UI::End();
        UI::PopStyleColor();
    }
}

void Main() {
    NextCampaign::Main();
}

void Render() {
    NextCampaign::Render();
}
