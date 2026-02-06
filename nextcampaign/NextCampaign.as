namespace NextCampaign
{
    const string CACHE_FILE = IO::FromStorageFolder("next_campaign_cache.json");

    Json::Value cache;
    bool cacheDirty = false;

    string nextCampaignName = "";
    uint nextCampaignTimestamp = 0;

    uint lastFetchAttempt = 0;

    // ===== INIT =====

    void Main()
    {
        LoadCache();
        startnew(UpdateLoop);
    }

    void LoadCache()
    {
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

    void SaveCache()
    {
        if (!cacheDirty) return;
        Json::ToFile(CACHE_FILE, cache, true);
        cacheDirty = false;
    }

    void ApplyCache()
    {
        if (cache.HasKey("nextCampaignName"))
            nextCampaignName = cache["nextCampaignName"];

        if (cache.HasKey("nextCampaignTimestamp"))
            nextCampaignTimestamp = cache["nextCampaignTimestamp"];
    }

    // ===== UPDATE LOOP =====

    void UpdateLoop()
    {
        while (true)
        {
            TryFetch();
            sleep(60000); // check once per minute
        }
    }

    void TryFetch()
    {
        // simple anti spam guard
        if (Time::Stamp - lastFetchAttempt < 30) return;
        lastFetchAttempt = Time::Stamp;

        Net::HttpRequest@ req = Net::HttpGet("https://nextcampaign.m8.no/campaign_info.json");

        uint start = Time::Stamp;
        while (!req.Finished() && Time::Stamp - start < 15)
            yield();

        if (!req.Finished() || req.ResponseCode() != 200)
            return;

        auto j = req.Json();

        if (!j.HasKey("currentCampaign") || !j.HasKey("endTimestamp"))
            return;

        string current = j["currentCampaign"];
        nextCampaignName = NextSeason(current);
        nextCampaignTimestamp = uint(j["endTimestamp"]);

        cache["nextCampaignName"] = nextCampaignName;
        cache["nextCampaignTimestamp"] = nextCampaignTimestamp;

        if (j.HasKey("nextRequestInSeconds")) {
            cache["nextFetchAfter"] = Time::Stamp + uint(j["nextRequestInSeconds"]);
        }

        cacheDirty = true;
        SaveCache();
    }

    // ===== SEASON LOGIC =====

    string NextSeason(const string &in current)
    {
        array<string> seasons = {"Winter", "Spring", "Summer", "Fall"};

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

    // ===== COUNTDOWN =====

    int GetDaysInMonth(int month, int year)
    {
        if (month == 2) {
            if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) return 29;
            return 28;
        }
        if (month == 4 || month == 6 || month == 9 || month == 11) return 30;
        return 31;
    }

    string GetCountdown()
    {
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

    void DrawCountdownDigit(int value, const string &in label, bool leadingZero = true)
    {
        float width = 60.0f; // Fixed width for each column
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
        
        UI::EndGroup();
    }

    void Render()
    {
        auto app = cast<CTrackMania>(GetApp());
        if (app.RootMap !is null || app.CurrentPlayground !is null)
            return;

        if (nextCampaignTimestamp == 0)
            return;

        uint64 nowStamp = Time::Stamp;
        uint64 targetStamp = uint64(nextCampaignTimestamp);

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

        string textName = "\\$fffNext: " + nextCampaignName;
        string releaseDate = "\\$fff" + Time::FormatString("%a, %d %B %Y at %H:%M ", int64(nextCampaignTimestamp));

        UI::PushStyleColor(UI::Col::WindowBg, vec4(0.4f, 0.2f, 0.6f, 0.9f));
        UI::Begin("NextCampaignOverlay", UI::WindowFlags::NoTitleBar | UI::WindowFlags::NoResize | UI::WindowFlags::NoScrollbar | UI::WindowFlags::AlwaysAutoResize);
        
        UI::Text("NextCampaign");
        UI::Text(textName);
        UI::Separator();
        
        if (UI::BeginTable("countdown", 4)) {
            UI::TableSetupColumn("mo", UI::TableColumnFlags::WidthFixed, 60.0f);
            UI::TableSetupColumn("d", UI::TableColumnFlags::WidthFixed, 60.0f);
            UI::TableSetupColumn("h", UI::TableColumnFlags::WidthFixed, 60.0f);
            UI::TableSetupColumn("m", UI::TableColumnFlags::WidthFixed, 60.0f);

            UI::TableNextColumn(); DrawCountdownDigit(months, "months", false);
            UI::TableNextColumn(); DrawCountdownDigit(days, "days", false);
            UI::TableNextColumn(); DrawCountdownDigit(hours, "hours");
            UI::TableNextColumn(); DrawCountdownDigit(mins, "minutes");
            UI::EndTable();
        }
        
        UI::Separator();
        UI::Text("Release date:");
        UI::Text(releaseDate);
        UI::Text("\\$fffWeb: nextcampaign.m8.no");
        UI::End();
        UI::PopStyleColor();
    }
}

void Main()
{
    NextCampaign::Main();
}

void Render()
{
    NextCampaign::Render();
}