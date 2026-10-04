--==================================================
-- BONA SERVER HOP
-- RAYFIELD GEN1
-- CONTINUOUS SERVER FINDER
--==================================================

local RayfieldSuccess, Rayfield = pcall(function()
    return loadstring(game:HttpGet(
        "https://sirius.menu/rayfield"
    ))()
end)

if not RayfieldSuccess or not Rayfield then
    warn("[BONA] Failed to load Rayfield")
    return
end

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlaceId = game.PlaceId
local CurrentJobId = game.JobId

local MaxPlayersWanted = 1
local SearchPages = 1000
local ServersPerPage = 100

local ServerHopEnabled = false
local Searching = false

local Window = Rayfield:CreateWindow({
    Name = "BONA Server Hop",
    LoadingTitle = "BONA Server Hop",
    LoadingSubtitle = "Gen1 • Continuous Server Finder",
    Theme = "Default",

    ConfigurationSaving = {
        Enabled = false,
        FolderName = "BONA",
        FileName = "ServerHop"
    },

    Discord = {
        Enabled = false
    },

    KeySystem = false
})

local ServerTab = Window:CreateTab(
    "Server",
    4483362458
)

local CurrentServerParagraph = ServerTab:CreateParagraph({
    Title = "Current Server",
    Content =
        "Players: " ..
        tostring(#Players:GetPlayers()) ..
        "\nMaximum Players: " ..
        tostring(Players.MaxPlayers) ..
        "\n\nServer ID:\n" ..
        tostring(CurrentJobId)
})

local StatusParagraph = ServerTab:CreateParagraph({
    Title = "Hop Status",
    Content =
        "Status: OFF\n" ..
        "Waiting..."
})

local function UpdateStatus(Text)
    StatusParagraph:Set({
        Title = "Hop Status",
        Content = Text
    })
end

ServerTab:CreateSlider({
    Name = "Max Players",
    Range = {1, 50},
    Increment = 1,
    Suffix = " Players",
    CurrentValue = 1,

    Callback = function(Value)
        MaxPlayersWanted = Value

        if ServerHopEnabled then
            UpdateStatus(
                "Status: ON\n" ..
                "Searching for " ..
                tostring(Value) ..
                " or fewer players..."
            )
        end
    end
})

ServerTab:CreateSlider({
    Name = "Server Search Pages",
    Range = {1, 1000},
    Increment = 1,
    Suffix = " Pages",
    CurrentValue = 1000,

    Callback = function(Value)
        SearchPages = Value
    end
})

local function FindMatchingServer()

    local Cursor = nil

    for Page = 1, SearchPages do

        if not ServerHopEnabled then
            return nil
        end

        UpdateStatus(
            "Status: SEARCHING\n" ..
            "Page: " ..
            tostring(Page) ..
            "/" ..
            tostring(SearchPages) ..
            "\nTarget: " ..
            tostring(MaxPlayersWanted) ..
            " or fewer players"
        )

        local URL =
            "https://games.roblox.com/v1/games/" ..
            tostring(PlaceId) ..
            "/servers/Public?sortOrder=Asc&limit=" ..
            tostring(ServersPerPage)

        if Cursor then
            URL =
                URL ..
                "&cursor=" ..
                HttpService:UrlEncode(Cursor)
        end

        local RequestSuccess, Response = pcall(function()
            return game:HttpGet(URL)
        end)

        if RequestSuccess and Response then

            local DecodeSuccess, Data = pcall(function()
                return HttpService:JSONDecode(Response)
            end)

            if DecodeSuccess and Data then

                if Data.data then

                    for _, Server in ipairs(Data.data) do

                        if not ServerHopEnabled then
                            return nil
                        end

                        local ServerId = Server.id
                        local Playing = tonumber(Server.playing) or 0
                        local MaxServerPlayers = tonumber(Server.maxPlayers) or 0

                        if ServerId ~= CurrentJobId then

                            if Playing < MaxServerPlayers then

                                if Playing <= MaxPlayersWanted then

                                    return {
                                        Id = ServerId,
                                        Playing = Playing,
                                        MaxPlayers = MaxServerPlayers
                                    }

                                end
                            end
                        end
                    end
                end

                Cursor = Data.nextPageCursor

                if not Cursor then
                    break
                end

            else
                warn("[BONA] Invalid server response")
            end

        else
            warn("[BONA] Server request failed")
        end

        task.wait(0.15)
    end

    return nil
end

local TeleportFailed = false
local TeleportFailureMessage = ""

--==================================================
-- TELEPORT FAILURE EVENT
--==================================================

pcall(function()
    TeleportService.TeleportInitFailed:Connect(function(
        Player,
        TeleportResult,
        ErrorMessage
    )

        if Player ~= LocalPlayer then
            return
        end

        TeleportFailed = true
        TeleportFailureMessage =
            tostring(ErrorMessage or TeleportResult or "Unknown error")

        warn(
            "[BONA] TeleportInitFailed: " ..
            TeleportFailureMessage
        )
    end)
end)

--==================================================
-- TELEPORT TO FOUND SERVER
--==================================================

local function TeleportToServer(Server)

    if not Server or not Server.Id then
        return false
    end

    if not ServerHopEnabled then
        return false
    end

    TeleportFailed = false
    TeleportFailureMessage = ""

    UpdateStatus(
        "Status: SERVER FOUND\n" ..
        "Players: " ..
        tostring(Server.Playing) ..
        "/" ..
        tostring(Server.MaxPlayers) ..
        "\nTeleporting..."
    )

    Rayfield:Notify({
        Title = "Server Found",
        Content =
            "Players: " ..
            tostring(Server.Playing) ..
            "/" ..
            tostring(Server.MaxPlayers) ..
            "\nJoining server...",
        Duration = 4
    })

    -- Give the server list a moment to settle before teleporting.
    task.wait(0.5)

    local Success, Error = pcall(function()
        TeleportService:TeleportToPlaceInstance(
            PlaceId,
            Server.Id,
            LocalPlayer
        )
    end)

    if not Success then

        warn(
            "[BONA] Teleport call failed: " ..
            tostring(Error)
        )

        return false
    end

    -- TeleportToPlaceInstance can return successfully while
    -- Roblox later reports that the teleport could not start.
    -- Give TeleportInitFailed a short window to report it.
    local CheckUntil = os.clock() + 3

    while os.clock() < CheckUntil do

        if not ServerHopEnabled then
            return false
        end

        if TeleportFailed then

            Rayfield:Notify({
                Title = "Server Join Failed",
                Content =
                    "That server is no longer available.\n" ..
                    "Searching for another one...",
                Duration = 3
            })

            return false
        end

        task.wait(0.1)
    end

    -- If Roblox accepted the teleport, the client should leave.
    -- Keep the loop alive only if the teleport did not actually
    -- begin and continue searching for another server.
    return true
end

--==================================================
-- CONTINUOUS SERVER HOP LOOP
--==================================================

local function StartServerHop()

    if Searching then
        return
    end

    Searching = true

    task.spawn(function()

        while ServerHopEnabled do

            local Server = FindMatchingServer()

            if not Server then

                if not ServerHopEnabled then
                    break
                end

                UpdateStatus(
                    "Status: WAITING\n" ..
                    "No matching server found.\n" ..
                    "Searching again..."
                )

                task.wait(2)

            else

                local TeleportStarted =
                    TeleportToServer(Server)

                if TeleportStarted then

                    -- Roblox accepted the teleport request.
                    -- Usually the client leaves immediately.
                    UpdateStatus(
                        "Status: JOINING\n" ..
                        "Server: " ..
                        tostring(Server.Playing) ..
                        "/" ..
                        tostring(Server.MaxPlayers)
                    )

                    -- Do not spam teleport requests while Roblox
                    -- is processing the current one.
                    task.wait(5)

                    -- If we are still here, the teleport did not
                    -- actually move us. Search for another server.
                    if ServerHopEnabled then

                        Rayfield:Notify({
                            Title = "Still Here",
                            Content =
                                "The server did not load.\n" ..
                                "Finding another server...",
                            Duration = 3
                        })

                    end

                else

                    if ServerHopEnabled then

                        UpdateStatus(
                            "Status: RETRYING\n" ..
                            "Selected server could not be joined.\n" ..
                            "Finding another server..."
                        )

                        task.wait(1)

                    end
                end
            end
        end

        Searching = false

        UpdateStatus(
            "Status: OFF\n" ..
            "Server Hop stopped."
        )
    end)
end

ServerTab:CreateToggle({
    Name = "Server Hop",
    CurrentValue = false,
    Flag = "ServerHopToggle",

    Callback = function(Value)

        ServerHopEnabled = Value

        if Value then

            UpdateStatus(
                "Status: ON\n" ..
                "Searching until a matching server is found..."
            )

            Rayfield:Notify({
                Title = "Server Hop ON",
                Content = "Searching continuously.",
                Duration = 3
            })

            StartServerHop()

        else

            UpdateStatus(
                "Status: OFF\n" ..
                "Server Hop stopped."
            )

            Rayfield:Notify({
                Title = "Server Hop OFF",
                Content = "Searching stopped.",
                Duration = 3
            })
        end
    end
})

ServerTab:CreateButton({
    Name = "Rejoin Current Server",

    Callback = function()

        ServerHopEnabled = false

        UpdateStatus(
            "Status: OFF\n" ..
            "Rejoining..."
        )

        Rayfield:Notify({
            Title = "Rejoining",
            Content = "Returning to current server...",
            Duration = 3
        })

        task.wait(0.5)

        pcall(function()
            TeleportService:TeleportToPlaceInstance(
                PlaceId,
                CurrentJobId,
                LocalPlayer
            )
        end)
    end
})

ServerTab:CreateButton({
    Name = "Refresh Server Info",

    Callback = function()

        CurrentServerParagraph:Set({
            Title = "Current Server",
            Content =
                "Players: " ..
                tostring(#Players:GetPlayers()) ..
                "\nMaximum Players: " ..
                tostring(Players.MaxPlayers) ..
                "\n\nServer ID:\n" ..
                tostring(game.JobId)
        })
    end
})

ServerTab:CreateParagraph({
    Title = "Server Hop Info",

    Content =
        "Server Hop is an ON/OFF function.\n\n" ..
        "ON = continuously search.\n\n" ..
        "OFF = stop searching.\n\n" ..
        "Max Players default: 1\n\n" ..
        "Search Pages default: 1000\n\n" ..
        "If a selected server disappears or becomes full, " ..
        "the script automatically searches for another one."
})

Rayfield:Notify({
    Title = "BONA Server Hop",
    Content = "Loaded • Max 1 player • 1000 pages",
    Duration = 5
})
