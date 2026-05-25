local addonName, ns = ...

-- =========================================================================
-- INTERNE VERSIONSNUMMER
-- =========================================================================
local internalVersion = "1.4 Frühlingshasen"

-- =========================================================================
-- WAS IST NEU? (CHANGELOG)
-- Hier kannst du für jedes Update einfach neue Zeilen hinzufügen oder ändern
-- =========================================================================
local changelogNotes = {
    "|cff00ff00Neu:|r Das Addon erkennt nun Items die du schon Besitzt hast und blendet diese auf Wunsch aus (Kann in den Optionen aktiviert oder deaktiviert werden).",
    "|cff00ff00Neu:|r Das Addon erkennt nun Items die du schon Besitzt hast und markiert diese mit einem Haken (Kann in den Optionen aktiviert oder deaktiviert werden).",
    "|cff00ff00Neu:|r Eine Warnung hinzugefügt, wenn man seine nicht aktive Skillung betrachtet."   
}

-- =========================================================================
-- AUSNAHMEN: DIESE ITEMS ALS "CHAMPION" ANZEIGEN (ID = true)
-- =========================================================================
local SeelenHelfer_ChampionItems = {
    [264507] = true,
    [265739] = true, 
}

-- =========================================================================
-- DATEN-WEICHE & STATE
-- =========================================================================
local selectedContent = "Raid"   
local selectedTab = "Gear"

local UpdateList
local TriggerUpdate

-- =========================================================================
-- INVENTAR SCANNER (Besessene Items) - GEFIXT
-- =========================================================================
local OwnedItemsCache = {}

local GetBagSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetBagItemID = C_Container and C_Container.GetContainerItemID or GetContainerItemID

local function ScanPlayerItems()
    wipe(OwnedItemsCache)
    
    -- 1. Angelegte Ausrüstung scannen (Slots 1 bis 19)
    for i = 1, 19 do
        local itemID = GetInventoryItemID("player", i)
        if itemID then OwnedItemsCache[itemID] = true end
    end
    
    -- 2. Taschen scannen (Rucksäcke 0 bis 4)
    for bag = 0, 4 do
        local numSlots = GetBagSlots(bag)
        if numSlots then
            for slot = 1, numSlots do
                local itemID = GetBagItemID(bag, slot)
                if itemID then OwnedItemsCache[itemID] = true end
            end
        end
    end
end

-- =========================================================================
-- HILFSFUNKTIONEN: DATEN & LOGIK & UI
-- =========================================================================
local function GetDisplayClassAndSpec()
    if SeelenHelferDB and not SeelenHelferDB.autoDetect then
        return SeelenHelferDB.manualClassID or 1, SeelenHelferDB.manualSpecID or 71
    else
        local _, _, classID = UnitClass("player")
        local specIndex = GetSpecialization and GetSpecialization() or 1
        local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex) or nil
        return classID, specID
    end
end

local function FormatDungeonName(key)
    if not key then return "Unbekannt" end
    local safeKey = tostring(key)
    local words = {}
    for word in string.gmatch(safeKey, "[^-]+") do
        table.insert(words, (word:gsub("^%l", string.upper)))
    end
    return table.concat(words, " ")
end

local function CreateModernButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
    btn:SetBackdropColor(0.2, 0.2, 0.2, 1); btn:SetBackdropBorderColor(0, 0, 0, 1)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER"); btn.text:SetText(text)
    return btn
end

local function GetCurrentDataList()
    local classID, specID = GetDisplayClassAndSpec()
    if not classID or not specID then return {} end

    if selectedTab == "Gear" then
        if ArchonBiS_Data and ArchonBiS_Data[classID] and ArchonBiS_Data[classID][specID] and ArchonBiS_Data[classID][specID][selectedContent] then
            return ArchonBiS_Data[classID][specID][selectedContent]["Archon"] or {}
        end
    elseif selectedTab == "Talents" then
        if ArchonTalentData and ArchonTalentData[classID] and ArchonTalentData[classID][specID] then
            local baseNode = ArchonTalentData[classID][specID]
            local talentNode = baseNode[selectedContent]
            if type(talentNode) ~= "table" and selectedContent == "Mythic+" and baseNode["all-dungeons"] then talentNode = baseNode end
            
            if type(talentNode) == "table" then
                local talentList = {}
                for encounterKey, data in pairs(talentNode) do
                    if type(data) == "table" and data.heroTalent then
                        table.insert(talentList, {
                            name = data.name or FormatDungeonName(encounterKey),
                            sortKey = tostring(encounterKey),
                            heroTalent = tostring(data.heroTalent or "Talent-Build"),
                            usage = tostring(data.usage or ""),
                            dps = tostring(data.dps or ""),
                            icon = tostring(data.icon or ""),
                            importString = tostring(data.importString or "")
                        })
                    end
                end
                table.sort(talentList, function(a, b)
                    local aIsAll = (a.sortKey == "all-dungeons" or a.sortKey == "all-bosses")
                    local bIsAll = (b.sortKey == "all-dungeons" or b.sortKey == "all-bosses")
                    if aIsAll and not bIsAll then return true end
                    if bIsAll and not aIsAll then return false end
                    return a.name < b.name
                end)
                return talentList
            end
        end
    elseif selectedTab == "Enchants" then
        if ArchonEnchantGemData and ArchonEnchantGemData[classID] and ArchonEnchantGemData[classID][specID] then
            return ArchonEnchantGemData[classID][specID][selectedContent] or {}
        end
    end
    return {}
end

local function IsItemBiS(itemID)
    if not itemID then return false end
    local classID, specID = GetDisplayClassAndSpec()
    if ArchonBiS_Data and ArchonBiS_Data[classID] and ArchonBiS_Data[classID][specID] and ArchonBiS_Data[classID][specID][selectedContent] then
        local itemList = ArchonBiS_Data[classID][specID][selectedContent]["Archon"]
        if itemList then
            for _, item in ipairs(itemList) do
                if tonumber(item.id) == itemID then return true end
            end
        end
    end
    return false
end

-- =========================================================================
-- 1. HAUPTFENSTER SETUP
-- =========================================================================
local MainFrame = CreateFrame("Frame", "SeelenHelfer_MainFrame", UIParent, "BackdropTemplate")
MainFrame:SetSize(550, 550) 
MainFrame:SetPoint("CENTER")
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:SetClampedToScreen(true)
MainFrame:SetResizable(true)

if MainFrame.SetResizeBounds then
    MainFrame:SetResizeBounds(550, 250, 550, 900)
elseif MainFrame.SetMinResize and MainFrame.SetMaxResize then
    MainFrame:SetMinResize(550, 250)
    MainFrame:SetMaxResize(550, 900)
end
MainFrame:Hide()

MainFrame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
MainFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
MainFrame:SetBackdropBorderColor(0, 0, 0, 1)

-- =========================================================================
-- RESIZE-HANDLE (DIAGONALE STREIFEN)
-- =========================================================================
local ResizeHandle = CreateFrame("Button", nil, MainFrame)
ResizeHandle:SetSize(16, 16)
ResizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)

ResizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
ResizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down") 
ResizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

ResizeHandle:SetScript("OnMouseDown", function() 
    if SeelenHelferDB and SeelenHelferDB.useManualHeight then MainFrame:StartSizing("BOTTOMRIGHT") end
end)
ResizeHandle:SetScript("OnMouseUp", function() 
    MainFrame:StopMovingOrSizing() 
    SeelenHelferDB.customHeight = MainFrame:GetHeight()
end)

-- =========================================================================
-- TITELZEILE
-- =========================================================================
local TitleBar = CreateFrame("Frame", nil, MainFrame)
TitleBar:SetSize(MainFrame:GetWidth(), 30)
TitleBar:SetPoint("TOPLEFT")
TitleBar:EnableMouse(true)
TitleBar:RegisterForDrag("LeftButton")
TitleBar:SetScript("OnDragStart", function() MainFrame:StartMoving() end)
TitleBar:SetScript("OnDragStop", function() MainFrame:StopMovingOrSizing() end)

local TitleBarBg = TitleBar:CreateTexture(nil, "BACKGROUND")
TitleBarBg:SetAllPoints(); TitleBarBg:SetColorTexture(0.1, 0.1, 0.1, 1)

MainFrame.logo = TitleBar:CreateTexture(nil, "OVERLAY")
MainFrame.logo:SetSize(20, 20); MainFrame.logo:SetPoint("LEFT", 10, 0)
MainFrame.logo:SetTexture("Interface\\AddOns\\SeelenHelfer\\logo")

MainFrame.title = TitleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
MainFrame.title:SetPoint("LEFT", MainFrame.logo, "RIGHT", 8, 0)
MainFrame.title:SetText("SeelenHelfer v" .. internalVersion)

local CloseButton = CreateFrame("Button", nil, TitleBar, "UIPanelCloseButton")
CloseButton:SetPoint("RIGHT", 0, 0); CloseButton:SetScript("OnClick", function() MainFrame:Hide() end)

local OptionsButton = CreateFrame("Button", nil, TitleBar)
OptionsButton:SetSize(22, 22); OptionsButton:SetPoint("RIGHT", CloseButton, "LEFT", -2, 0)
OptionsButton:SetNormalTexture("Interface\\GossipFrame\\WorkOrderGossipIcon")
OptionsButton:SetHighlightTexture("Interface\\GossipFrame\\WorkOrderGossipIcon", "ADD")

-- NEU: Falsche Skillung Warnung (Jetzt mittig und größer)
MainFrame.wrongSpecWarning = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- 'GameFontNormalLarge' macht den Text deutlich größer
MainFrame.wrongSpecWarning:SetPoint("TOP", MainFrame, "TOP", 0, -68) -- 'TOP' und X=0 zentrieren den Text horizontal
MainFrame.wrongSpecWarning:SetText("|cffff0000Achtung: Du betrachtest nicht deine aktuell aktive Skillung!|r")
MainFrame.wrongSpecWarning:Hide()

MainFrame.statPrioInfo = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
MainFrame.statPrioInfo:SetPoint("TOPLEFT", 15, -85) -- Etwas nach unten verschoben für die Warnung
MainFrame.specInfo = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
MainFrame.specInfo:SetPoint("BOTTOMLEFT", 15, 12)
MainFrame.dateInfo = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
MainFrame.dateInfo:SetPoint("BOTTOMRIGHT", -15, 12)

-- =========================================================================
-- 2. TABS & DROPDOWN
-- =========================================================================
local btnRaid = CreateModernButton(MainFrame, "Raid", 75, 22); btnRaid:SetPoint("TOPLEFT", 15, -40)
local btnMythic = CreateModernButton(MainFrame, "Mythic+", 75, 22); btnMythic:SetPoint("LEFT", btnRaid, "RIGHT", 5, 0)
local btnClassSpec = CreateModernButton(MainFrame, "Klasse / Spec", 120, 22); btnClassSpec:SetPoint("TOPRIGHT", -15, -40)

btnClassSpec:SetScript("OnMouseDown", function(self)
    if not MenuUtil then return end
    MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
        rootDescription:CreateRadio("|cff00ff00Automatische Erkennung|r", function() return SeelenHelferDB.autoDetect end, function() SeelenHelferDB.autoDetect = true; TriggerUpdate() end)
        rootDescription:CreateDivider()
        for i = 1, GetNumClasses() do
            local className, _, classID = GetClassInfo(i)
            if className then
                local classButton = rootDescription:CreateButton(className)
                local numSpecs = GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(classID) or 0
                for s = 1, numSpecs do
                    local specID, specName = GetSpecializationInfoForClassID(classID, s)
                    classButton:CreateRadio(specName, function() return (not SeelenHelferDB.autoDetect) and (SeelenHelferDB.manualClassID == classID) and (SeelenHelferDB.manualSpecID == specID) end,
                    function() SeelenHelferDB.autoDetect = false; SeelenHelferDB.manualClassID = classID; SeelenHelferDB.manualSpecID = specID; TriggerUpdate() end)
                end
            end
        end
    end)
end)

local tW = 95
local btnTabGear = CreateModernButton(MainFrame, "BiS Gear", tW, 22); btnTabGear:SetPoint("BOTTOMLEFT", 15, 35)
local btnTabTalents = CreateModernButton(MainFrame, "Talente", tW, 22); btnTabTalents:SetPoint("LEFT", btnTabGear, "RIGHT", 5, 0)
local btnTabEnchants = CreateModernButton(MainFrame, "Verz./Edel.", tW, 22); btnTabEnchants:SetPoint("LEFT", btnTabTalents, "RIGHT", 5, 0)

btnRaid:SetScript("OnClick", function() selectedContent = "Raid"; TriggerUpdate() end)
btnMythic:SetScript("OnClick", function() selectedContent = "Mythic+"; TriggerUpdate() end)
btnTabGear:SetScript("OnClick", function() selectedTab = "Gear"; TriggerUpdate() end)
btnTabTalents:SetScript("OnClick", function() selectedTab = "Talents"; TriggerUpdate() end)
btnTabEnchants:SetScript("OnClick", function() selectedTab = "Enchants"; TriggerUpdate() end)

local ScrollFrame = CreateFrame("ScrollFrame", "SeelenHelfer_ScrollFrame", MainFrame, "UIPanelScrollFrameTemplate")
ScrollFrame:SetPoint("TOPLEFT", 10, -105); ScrollFrame:SetPoint("BOTTOMRIGHT", -30, 65)

if ScrollFrame.ScrollBar then
    ScrollFrame.ScrollBar:Hide(); ScrollFrame.ScrollBar:ClearAllPoints()
    ScrollFrame.ScrollBar:SetPoint("TOPLEFT", ScrollFrame, "TOPRIGHT", 5, -16)
    ScrollFrame.ScrollBar:SetPoint("BOTTOMLEFT", ScrollFrame, "BOTTOMRIGHT", 5, 16)
end

local ContentFrame = CreateFrame("Frame", nil, ScrollFrame)
ContentFrame:SetSize(520, 1); ScrollFrame:SetScrollChild(ContentFrame)

ScrollFrame:EnableMouseWheel(true)
ScrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, ContentFrame:GetHeight() - self:GetHeight())
    local newScroll = self:GetVerticalScroll() - (delta * 44)
    self:SetVerticalScroll(math.max(0, math.min(newScroll, maxScroll)))
end)

StaticPopupDialogs["SEELENHELFER_COPY_TALENTS"] = {
    text = "Talent-String kopieren (Strg+C):", button1 = "Schließen", hasEditBox = 1, editBoxWidth = 350,
    OnShow = function(self, data)
        local eb = self.editBox or _G[self:GetName().."EditBox"] or self.EditBox
        if eb then eb:SetText(data or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- =========================================================================
-- UPDATE LISTE (RENDERING)
-- =========================================================================
UpdateList = function()
    btnRaid:SetBackdropColor(selectedContent == "Raid" and 0.4 or 0.2, selectedContent == "Raid" and 0.4 or 0.2, selectedContent == "Raid" and 0.4 or 0.2, 1)
    btnMythic:SetBackdropColor(selectedContent == "Mythic+" and 0.4 or 0.2, selectedContent == "Mythic+" and 0.4 or 0.2, selectedContent == "Mythic+" and 0.4 or 0.2, 1)
    btnTabGear:SetBackdropColor(selectedTab == "Gear" and 0.5 or 0.2, selectedTab == "Gear" and 0.5 or 0.2, selectedTab == "Gear" and 0.5 or 0.2, 1)
    btnTabTalents:SetBackdropColor(selectedTab == "Talents" and 0.5 or 0.2, selectedTab == "Talents" and 0.5 or 0.2, selectedTab == "Talents" and 0.5 or 0.2, 1)
    btnTabEnchants:SetBackdropColor(selectedTab == "Enchants" and 0.5 or 0.2, selectedTab == "Enchants" and 0.5 or 0.2, selectedTab == "Enchants" and 0.5 or 0.2, 1)

    if ContentFrame.lines then for _, l in pairs(ContentFrame.lines) do l:Hide() end end
    ContentFrame.lines = {}

    local cID, sID = GetDisplayClassAndSpec()
    local cName, cFile = GetClassInfo(cID or 1)
    local sName = "Unbekannt"
    if GetSpecializationInfoByID and sID then
        _, sName = GetSpecializationInfoByID(sID)
    end
    
    -- Aktive Skillung auslesen um sie mit der betrachteten abzugleichen
    local _, _, actualClassID = UnitClass("player")
    local actualSpecID = GetSpecializationInfo and GetSpecializationInfo(GetSpecialization() or 1)
    
    if cID ~= actualClassID or sID ~= actualSpecID then
        MainFrame.wrongSpecWarning:Show()
    else
        MainFrame.wrongSpecWarning:Hide()
    end
    
    MainFrame.specInfo:SetText(SeelenHelferDB.autoDetect and "|cffffd700Aktuell: " .. (sName or "") .. "|r" or "|cff00ff00Manuell: " .. (sName or "") .. "|r")
    MainFrame.dateInfo:SetText("Stand: " .. (ArchonBiS_Date or "Unbekannt"))

    local rawDataList = GetCurrentDataList()
    local dataList = {}
    
    -- Filter Logik: Besessene Items verstecken
    for _, itemData in ipairs(rawDataList) do
        local iID = tonumber(itemData.id)
        local isOwned = iID and OwnedItemsCache[iID]
        if not (selectedTab == "Gear" and isOwned and SeelenHelferDB.hideOwnedItems) then
            table.insert(dataList, itemData)
        end
    end
    
    if selectedTab == "Gear" then
        local st = "Keine Daten"
        if ArchonBiS_Data[cID] and ArchonBiS_Data[cID][sID] and ArchonBiS_Data[cID][sID][selectedContent] then
            st = ArchonBiS_Data[cID][sID][selectedContent]["StatPriority"] or "Keine Stat-Prio gefunden"
        end
        if SeelenHelferDB and SeelenHelferDB.showStatWeights == false then
            st = string.gsub(st, "%s*%([%d%,%.]+%)", "")
        else
            st = string.gsub(st, "(%([%d%,%.]+%))", "|cffffff00%1|r|cff00ff00")
        end
        MainFrame.statPrioInfo:SetText("Stat-Prio: |cff00ff00" .. st .. "|r")
    elseif selectedTab == "Talents" then
        MainFrame.statPrioInfo:SetText("|cff00ff00Links-Klick:|r Import   |cff888888-|r   |cff00ccffRechts-Klick:|r Vorschau")
    elseif selectedTab == "Enchants" then
        MainFrame.statPrioInfo:SetText("Empfohlene Verzauberungen & Edelsteine für |cff00ff00" .. selectedContent .. "|r")
        if #dataList > 0 then
            local g = { enchants = {}, epic = {}, normal = {} }
            for _, item in ipairs(dataList) do
                if item.typ == "epic gem" then table.insert(g.epic, item)
                elseif item.typ == "gem" then table.insert(g.normal, item)
                else table.insert(g.enchants, item) end
            end
            dataList = {}
            if #g.enchants > 0 then table.insert(dataList, { isHeader = true, title = "Verzauberungen" }); for _, v in ipairs(g.enchants) do table.insert(dataList, v) end end
            if #g.epic > 0 then table.insert(dataList, { isHeader = true, title = "Epischer Edelstein" }); for _, v in ipairs(g.epic) do table.insert(dataList, v) end end
            if #g.normal > 0 then table.insert(dataList, { isHeader = true, title = "Edelsteine" }); for _, v in ipairs(g.normal) do table.insert(dataList, v) end end
        end
    end

    local yO = 0
    if #dataList == 0 then
        local msg = ContentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        msg:SetPoint("TOP", ContentFrame, "TOP", 0, -20)
        if selectedTab == "Gear" and #rawDataList > 0 and SeelenHelferDB.hideOwnedItems then
            msg:SetText("|cff00ff00Herzlichen Glückwunsch! Du hast bereits alle BiS-Items!|r\n")
        else
            msg:SetText("Noch keine Daten für diesen Bereich vorhanden.\n")
        end
        msg:Show(); table.insert(ContentFrame.lines, msg)
        yO = -100
    else
        for i, itemData in ipairs(dataList) do
            if itemData.isHeader then
                local h = CreateFrame("Frame", nil, ContentFrame)
                h:SetSize(510, 25); h:SetPoint("TOPLEFT", 5, yO)
                local t = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                t:SetPoint("BOTTOMLEFT", 10, 5); t:SetText("|cffffd700" .. itemData.title .. "|r")
                local l = h:CreateTexture(nil, "BACKGROUND")
                l:SetColorTexture(1, 0.84, 0, 0.3); l:SetSize(490, 1); l:SetPoint("BOTTOMLEFT", 10, 0)
                h:Show(); table.insert(ContentFrame.lines, h); yO = yO - 30
            else
                local line = CreateFrame("Button", nil, ContentFrame, "BackdropTemplate")
                line:SetSize(510, 42); line:SetPoint("TOPLEFT", 5, yO)
                local bC = (i % 2 == 0) and 0.15 or 0.1
                line:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" }); line:SetBackdropColor(1, 1, 1, bC)

                if selectedTab == "Gear" or selectedTab == "Enchants" then
                    local iID = tonumber(itemData.id)
                    local bonusIDs = "2:12796:13334:"
                    if iID and SeelenHelfer_ChampionItems[iID] then bonusIDs = "1:12790::" end
                    local finalLink = "item:"..(iID or 0).."::::::::::::"..bonusIDs
                    if selectedTab == "Enchants" then finalLink = "item:"..(iID or 0) end
                    local fullLink = "|H"..finalLink.."|h[ ]|h"
                    
                    local iL, iT
                    if C_Item and C_Item.GetItemInfo then
                        _, iL, _, _, _, _, _, _, _, iT = C_Item.GetItemInfo(fullLink)
                        if not iL and iID and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(iID) end
                    else
                        _, iL, _, _, _, _, _, _, _, iT = GetItemInfo(fullLink)
                    end
                    
                    local icon = line:CreateTexture(nil, "ARTWORK"); icon:SetSize(34, 34); icon:SetPoint("LEFT", 5, 0); icon:SetTexture(iT or 134400)
                    
                    -- BiS Star & Checkmark
                    if selectedTab == "Gear" then                        
                        
                        if iID and OwnedItemsCache[iID] and SeelenHelferDB.showOwnedCheckmark then
                            local check = line:CreateTexture(nil, "OVERLAY")
                            check:SetSize(22, 22)
                            check:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 6, -6)
                            check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                        end
                    end
                    
                    local t1 = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); t1:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2); t1:SetTextColor(0.6, 0.6, 0.6); t1:SetText(itemData.slot or "Slot")
                    local t2 = line:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t2:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 2); t2:SetText(iL or itemData.name or "Lade...")
                    
                    local u = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); u:SetPoint("RIGHT", -10, 0)
                    local sourceString = itemData.source or ""
                    if selectedTab == "Gear" and (SeelenHelferDB and SeelenHelferDB.showArchonPercentages ~= false) and itemData.percentage and itemData.percentage ~= "" then
                        sourceString = sourceString .. " |cff00ff00[" .. itemData.percentage .. "]|r"
                    elseif selectedTab == "Enchants" and itemData.usage then
                        sourceString = "|cff00ff00" .. itemData.usage .. "|r"
                    end
                    u:SetText(sourceString)
                    
                    line:SetScript("OnEnter", function(self) self:SetBackdropColor(1,1,1,0.25); if iID then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(fullLink); GameTooltip:Show() end end)
                    line:SetScript("OnLeave", function(self) self:SetBackdropColor(1,1,1,bC); GameTooltip:Hide() end)
                    
                    if selectedTab == "Gear" then
                        line:SetScript("OnClick", function()
                            local numInst = tonumber(itemData.instanceID); local numBoss = tonumber(itemData.encounterID)
                            if (numInst and numInst > 0) or (numBoss and numBoss > 0) then
                                if not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then C_AddOns.LoadAddOn("Blizzard_EncounterJournal") end
                                if EncounterJournal_OpenJournal then EncounterJournal_OpenJournal(nil, numInst, numBoss, nil, nil, iID) end
                            end
                        end)
                    end
                elseif selectedTab == "Talents" then
                    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    local icon = line:CreateTexture(nil, "ARTWORK"); icon:SetSize(34, 34); icon:SetPoint("LEFT", 5, 0)
                    if itemData.icon and cFile then icon:SetAtlas("talents-heroclass-" .. string.lower(cFile) .. "-" .. string.lower(itemData.icon):gsub("['%s]", "")) end
                    local t1 = line:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t1:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2); t1:SetText("|cffffffff" .. itemData.name .. "|r |cff888888-|r |cffffd700" .. itemData.heroTalent .. "|r")
                    local t2 = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t2:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 2); t2:SetText("Nutzung: |cff00ff00" .. itemData.usage .. "|r  |cff888888-|r  DPS: |cffffffff" .. itemData.dps .. "|r")
                    
                    line:SetScript("OnClick", function(_, btn)
                        local clean = string.gsub(itemData.importString, "%s+", "")
                        if btn == "RightButton" then 
                            local tLink = "talentbuild:" .. (sID or 1) .. ":" .. (UnitLevel("player") or 80) .. ":" .. clean
                            SetItemRef(tLink, "|H" .. tLink .. "|h[Talente]|h", "LeftButton")
                        else 
                            StaticPopup_Show("SEELENHELFER_COPY_TALENTS", "", "", clean) 
                        end
                    end)
                    
                    line:SetScript("OnEnter", function(self) self:SetBackdropColor(1,1,1,0.25) end)
                    line:SetScript("OnLeave", function(self) self:SetBackdropColor(1,1,1,bC) end)
                end
                line:Show(); table.insert(ContentFrame.lines, line); yO = yO - 44
            end
        end
    end
    
    local listH = math.abs(yO)
    ContentFrame:SetHeight(listH)
    
    if SeelenHelferDB and SeelenHelferDB.useManualHeight then
        ResizeHandle:Show()
        if SeelenHelferDB.customHeight then MainFrame:SetHeight(SeelenHelferDB.customHeight) end
    else
        local tH = 195 + listH
        local point, relativeTo, relativePoint, xOfs, yOfs = MainFrame:GetPoint(1)
        if point then
            MainFrame:ClearAllPoints()
            MainFrame:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
        end
        MainFrame:SetHeight(math.max(250, math.min(900, tH)))
        ResizeHandle:Hide()
    end
    
    if ScrollFrame.ScrollBar then
        if listH > ScrollFrame:GetHeight() then ScrollFrame.ScrollBar:Show() else ScrollFrame.ScrollBar:Hide() end
    end
end

TriggerUpdate = function() if MainFrame:IsShown() then UpdateList() end end

-- =========================================================================
-- TOOLTIP & OVERLAYS (Taint-Sicher mit Weak Tables!)
-- =========================================================================
if TooltipDataProcessor then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(t, d)
        if d and d.id and IsItemBiS(d.id) then t:AddLine(" "); t:AddLine("|TInterface\\AddOns\\SeelenHelfer\\bis:16:16:0:0|t |cffffd700SeelenHelfer: Best in Slot|r") end
    end)
end

local BagOverlays = setmetatable({}, {__mode = "k"})

local function UpdOvl(b, i)
    if not b then return end
    if not BagOverlays[b] then 
        BagOverlays[b] = b:CreateTexture(nil, "OVERLAY")
        BagOverlays[b]:SetSize(14, 14)
        BagOverlays[b]:SetPoint("TOPRIGHT", 2, 2)
        BagOverlays[b]:SetTexture("Interface\\AddOns\\SeelenHelfer\\bis") 
    end
    BagOverlays[b]:SetShown(i and IsItemBiS(i))
end

if ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.UpdateItem then
    hooksecurefunc(ContainerFrameItemButtonMixin, "UpdateItem", function(s) UpdOvl(s, s:GetItemID()) end)
elseif ContainerFrameItemButton_Update then
    hooksecurefunc("ContainerFrameItemButton_Update", function(b) local bId, sId = b:GetParent():GetID(), b:GetID(); UpdOvl(b, C_Container and C_Container.GetContainerItemID(bId, sId) or GetContainerItemID(bId, sId)) end)
end

if PaperDollItemSlotButton_Update then
    hooksecurefunc("PaperDollItemSlotButton_Update", function(s) UpdOvl(s, GetInventoryItemID("player", s:GetID())) end)
end

-- =========================================================================
-- MINIMAP SETUP & FUNKTION (Perfekte Zentrierung & Viereck Support)
-- =========================================================================
local Mini = CreateFrame("Button", "SeelenHelfer_Mini", Minimap)
Mini:SetSize(32, 32)
Mini:SetFrameStrata("MEDIUM")
Mini:SetFrameLevel(8)
Mini:EnableMouse(true)
Mini:RegisterForDrag("LeftButton")

Mini.icon = Mini:CreateTexture(nil, "BACKGROUND")
Mini.icon:SetTexture("Interface\\AddOns\\SeelenHelfer\\logo")
Mini.icon:SetSize(20, 20)
Mini.icon:SetPoint("TOPLEFT", Mini, "TOPLEFT", 7, -6)

Mini.border = Mini:CreateTexture(nil, "OVERLAY")
Mini.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
Mini.border:SetSize(54, 54)
Mini.border:SetPoint("TOPLEFT", Mini, "TOPLEFT", 0, 0)

local function UpdateMinimapPos(angle) 
    if not angle then return end
    local radius = (Minimap:GetWidth() / 2) + 5 
    local isSquare = false 
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then isSquare = true end
    if ElvUI or Tukui then isSquare = true end

    local x = math.cos(angle)
    local y = math.sin(angle)
    
    if isSquare then
        local q = math.max(math.abs(x), math.abs(y))
        x = x / q; y = y / q
    end
    Mini:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius) 
end

Mini:SetScript("OnDragStart", function(self) 
    self:SetScript("OnUpdate", function() 
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local sc = Minimap:GetEffectiveScale()
        if not mx or not my or not cx or not cy or not sc then return end
        local angle = math.atan2((cy/sc) - my, (cx/sc) - mx)
        SeelenHelferDB.minimapPos = angle
        UpdateMinimapPos(angle) 
    end) 
end)
Mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
Mini:SetScript("OnClick", function() SlashCmdList["SEELENHELFER"]("") end)

-- =========================================================================
-- CHANGELOG FENSTER (WAS IST NEU)
-- =========================================================================
local ChangelogFrame = CreateFrame("Frame", "SeelenHelfer_ChangelogFrame", UIParent, "BackdropTemplate")
ChangelogFrame:SetSize(400, 300)
ChangelogFrame:SetPoint("CENTER")
ChangelogFrame:SetFrameStrata("DIALOG")
ChangelogFrame:EnableMouse(true)
ChangelogFrame:SetMovable(true)
ChangelogFrame:RegisterForDrag("LeftButton")
ChangelogFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
ChangelogFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
ChangelogFrame:Hide()

ChangelogFrame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
ChangelogFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
ChangelogFrame:SetBackdropBorderColor(0, 0, 0, 1)

local CL_TitleBar = CreateFrame("Frame", nil, ChangelogFrame)
CL_TitleBar:SetSize(400, 30)
CL_TitleBar:SetPoint("TOPLEFT")
local CL_TitleBarBg = CL_TitleBar:CreateTexture(nil, "BACKGROUND")
CL_TitleBarBg:SetAllPoints(); CL_TitleBarBg:SetColorTexture(0.1, 0.1, 0.1, 1)

local CL_Title = CL_TitleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
CL_Title:SetPoint("CENTER")
CL_Title:SetText("|cffffd700Was ist neu in v" .. internalVersion .. "?|r")

local CL_Text = ChangelogFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
CL_Text:SetPoint("TOPLEFT", 20, -50)
CL_Text:SetPoint("BOTTOMRIGHT", -20, 80)
CL_Text:SetJustifyH("LEFT")
CL_Text:SetJustifyV("TOP")
CL_Text:SetSpacing(8)
CL_Text:SetText(table.concat(changelogNotes, "\n"))

local CL_Checkbox = CreateFrame("CheckButton", nil, ChangelogFrame, "UICheckButtonTemplate")
CL_Checkbox:SetPoint("BOTTOMLEFT", 15, 45)
CL_Checkbox:SetChecked(true)
local CL_CheckboxLbl = ChangelogFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
CL_CheckboxLbl:SetPoint("LEFT", CL_Checkbox, "RIGHT", 5, 0)
CL_CheckboxLbl:SetText("Für dieses Update nicht mehr anzeigen")

local CL_CloseBtn = CreateModernButton(ChangelogFrame, "Schließen", 120, 25)
CL_CloseBtn:SetPoint("BOTTOM", 0, 15)
CL_CloseBtn:SetScript("OnClick", function()
    if CL_Checkbox:GetChecked() then
        SeelenHelferDB.lastSeenVersion = internalVersion
    end
    ChangelogFrame:Hide()
end)

-- =========================================================================
-- INIT & EVENTS
-- =========================================================================
local Init = CreateFrame("Frame"); 
Init:RegisterEvent("PLAYER_LOGIN")
Init:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
Init:RegisterEvent("GET_ITEM_INFO_RECEIVED")
Init:RegisterEvent("BAG_UPDATE")
Init:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

Init:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        SeelenHelferDB = SeelenHelferDB or {}
        
        if SeelenHelferDB.useManualHeight == nil then SeelenHelferDB.useManualHeight = true end
        if SeelenHelferDB.customHeight == nil then SeelenHelferDB.customHeight = 550 end
        if SeelenHelferDB.autoDetect == nil then SeelenHelferDB.autoDetect = true end
        if SeelenHelferDB.showArchonPercentages == nil then SeelenHelferDB.showArchonPercentages = true end
        if SeelenHelferDB.showStatWeights == nil then SeelenHelferDB.showStatWeights = true end
        
        if SeelenHelferDB.showOwnedCheckmark == nil then SeelenHelferDB.showOwnedCheckmark = true end
        if SeelenHelferDB.hideOwnedItems == nil then SeelenHelferDB.hideOwnedItems = false end
        
        SeelenHelferDB.uiScale = SeelenHelferDB.uiScale or 1.0
        SeelenHelferDB.defaultContent = SeelenHelferDB.defaultContent or "Raid"
        SeelenHelferDB.minimapPos = tonumber(SeelenHelferDB.minimapPos) or 4.5
        
        local _, _, cID = UnitClass("player")
        SeelenHelferDB.manualClassID = SeelenHelferDB.manualClassID or cID
        SeelenHelferDB.manualSpecID = SeelenHelferDB.manualSpecID or (GetSpecializationInfo and GetSpecializationInfo(GetSpecialization() or 1)) or 71
        
        MainFrame:SetScale(SeelenHelferDB.uiScale)
        selectedContent = SeelenHelferDB.defaultContent
        
        Mini:ClearAllPoints()
        UpdateMinimapPos(SeelenHelferDB.minimapPos)
        
        ScanPlayerItems()
        
        if SeelenHelferDB.lastSeenVersion ~= internalVersion then
            ChangelogFrame:Show()
        end
        
        print("|cffffd700SeelenHelfer v" .. internalVersion .. "|r erfolgreich geladen. Tippe /sh zum Öffnen.")
    elseif event == "GET_ITEM_INFO_RECEIVED" and MainFrame:IsShown() then
        UpdateList()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" and MainFrame:IsShown() then
        UpdateList()
    elseif event == "BAG_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED" then
        ScanPlayerItems()
        if MainFrame:IsShown() then UpdateList() end
    end
end)

SLASH_SEELENHELFER1 = "/sh"
SlashCmdList["SEELENHELFER"] = function(msg) 
    if msg == "opt" or msg == "options" then Settings.OpenToCategory(SeelenHelfer_OptionsCategory)
    elseif MainFrame:IsShown() then MainFrame:Hide() else MainFrame:Show(); UpdateList() end 
end

-- =========================================================================
-- OPTIONS PAGE SETUP
-- =========================================================================
local OF = CreateFrame("Frame", "SeelenHelfer_OptionsFrame")
OF.bg = OF:CreateTexture(nil, "BACKGROUND"); OF.bg:SetAllPoints(); OF.bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)

local optTitle = OF:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); optTitle:SetPoint("TOPLEFT", 16, -16); optTitle:SetText("SeelenHelfer v" .. internalVersion)

local optContentLbl = OF:CreateFontString(nil, "OVERLAY", "GameFontNormal"); optContentLbl:SetPoint("TOPLEFT", 16, -60); optContentLbl:SetText("Standard-Content beim Start:")
local btnDefRaid = CreateModernButton(OF, "Raid", 80, 25); btnDefRaid:SetPoint("LEFT", optContentLbl, "RIGHT", 32, 0)
local btnDefMythic = CreateModernButton(OF, "Mythic+", 80, 25); btnDefMythic:SetPoint("LEFT", btnDefRaid, "RIGHT", 5, 0)
local function UpdateDefaultButtons()
    SeelenHelferDB = SeelenHelferDB or {}
    btnDefRaid:SetBackdropColor(SeelenHelferDB.defaultContent == "Raid" and 0.4 or 0.2, 0.2, 0.2, 1)
    btnDefMythic:SetBackdropColor(SeelenHelferDB.defaultContent == "Mythic+" and 0.4 or 0.2, 0.2, 0.2, 1)
end
btnDefRaid:SetScript("OnClick", function() SeelenHelferDB.defaultContent = "Raid"; selectedContent = "Raid"; UpdateDefaultButtons(); TriggerUpdate() end)
btnDefMythic:SetScript("OnClick", function() SeelenHelferDB.defaultContent = "Mythic+"; selectedContent = "Mythic+"; UpdateDefaultButtons(); TriggerUpdate() end)

local optScaleLbl = OF:CreateFontString(nil, "OVERLAY", "GameFontNormal"); optScaleLbl:SetPoint("TOPLEFT", 16, -110); optScaleLbl:SetText("Fenster-Skalierung:")
local scaleSlider = CreateFrame("Slider", "SeelenHelfer_ScaleSlider", OF, "OptionsSliderTemplate")
scaleSlider:SetPoint("LEFT", optScaleLbl, "RIGHT", 20, 0); scaleSlider:SetMinMaxValues(0.5, 1.5); scaleSlider:SetValueStep(0.05); scaleSlider:SetObeyStepOnDrag(true)
_G[scaleSlider:GetName() .. 'Low']:SetText('50%'); _G[scaleSlider:GetName() .. 'High']:SetText('150%')
scaleSlider:SetScript("OnValueChanged", function(self, value) _G[self:GetName() .. 'Text']:SetText(string.format("Größe: %d%%", value * 100)) end)
scaleSlider:SetScript("OnMouseUp", function(self) local v = self:GetValue(); SeelenHelferDB.uiScale = v; MainFrame:SetScale(v) end)

local autoCheck = CreateFrame("CheckButton", nil, OF, "UICheckButtonTemplate"); autoCheck:SetPoint("TOPLEFT", 16, -150)
local autoCheckLbl = OF:CreateFontString(nil, "OVERLAY", "GameFontNormal"); autoCheckLbl:SetPoint("LEFT", autoCheck, "RIGHT", 5, 0); autoCheckLbl:SetText("Automatische Erkennung (Zeigt den aktuell gespielten Charakter an)")
autoCheck:SetScript("OnClick", function(s) SeelenHelferDB.autoDetect = s:GetChecked(); TriggerUpdate() end)

local pctCheck = CreateFrame("CheckButton", nil, OF, "UICheckButtonTemplate"); pctCheck:SetPoint("TOPLEFT", 16, -190)
local pctCheckLbl = OF:CreateFontString(nil, "OVERLAY", "GameFontNormal"); pctCheckLbl:SetPoint("LEFT", pctCheck, "RIGHT", 5, 0); pctCheckLbl:SetText("Prozentzahlen bei Archon-Daten anzeigen")
pctCheck:SetScript("OnClick", function(s) SeelenHelferDB.showArchonPercentages = s:GetChecked(); TriggerUpdate() end)

local statWeightCheck = CreateFrame("CheckButton", nil, OF, "UICheckButtonTemplate"); statWeightCheck:SetPoint("TOPLEFT", 16, -230)
local statWeightCheckLbl = OF:CreateFontString(nil, "OVERLAY", "GameFontNormal"); statWeightCheckLbl:SetPoint("LEFT", statWeightCheck, "RIGHT", 5, 0); statWeightCheckLbl:SetText("Werte in der Stat-Priorität anzeigen")
statWeightCheck:SetScript("OnClick", function(s) SeelenHelferDB.showStatWeights = s:GetChecked(); TriggerUpdate() end)

local manualCheck = CreateFrame("CheckButton", nil, OF, "UICheckButtonTemplate"); manualCheck:SetPoint("TOPLEFT", 16, -270)
local manualLbl = OF:CreateFontString(nil, "OVERLAY", "GameFontNormal"); manualLbl:SetPoint("LEFT", manualCheck, "RIGHT", 5, 0); manualLbl:SetText("Manuelle Fensterhöhe (Ermöglicht Ziehen unten rechts)")
manualCheck:SetScript("OnClick", function(s) SeelenHelferDB.useManualHeight = s:GetChecked(); TriggerUpdate() end)

local showOwnedCheck = CreateFrame("CheckButton", nil, OF, "UICheckButtonTemplate"); showOwnedCheck:SetPoint("TOPLEFT", 16, -310)
local showOwnedLbl = OF:CreateFontString(nil, "OVERLAY", "GameFontNormal"); showOwnedLbl:SetPoint("LEFT", showOwnedCheck, "RIGHT", 5, 0); showOwnedLbl:SetText("Grünen Haken anzeigen, wenn sich das Item im Inventar befindet")
showOwnedCheck:SetScript("OnClick", function(s) SeelenHelferDB.showOwnedCheckmark = s:GetChecked(); TriggerUpdate() end)

local hideOwnedCheck = CreateFrame("CheckButton", nil, OF, "UICheckButtonTemplate"); hideOwnedCheck:SetPoint("TOPLEFT", 16, -350)
local hideOwnedLbl = OF:CreateFontString(nil, "OVERLAY", "GameFontNormal"); hideOwnedLbl:SetPoint("LEFT", hideOwnedCheck, "RIGHT", 5, 0); hideOwnedLbl:SetText("BIS Items die Ihr Besitzt komplett aus der BiS-Liste ausblenden")
hideOwnedCheck:SetScript("OnClick", function(s) SeelenHelferDB.hideOwnedItems = s:GetChecked(); TriggerUpdate() end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(OF, "SeelenHelfer"); Settings.RegisterAddOnCategory(cat)
    SeelenHelfer_OptionsCategory = cat.ID
    OptionsButton:SetScript("OnClick", function() Settings.OpenToCategory(cat.ID) end)
end

OF:SetScript("OnShow", function() 
    UpdateDefaultButtons()
    scaleSlider:SetValue(SeelenHelferDB and SeelenHelferDB.uiScale or 1.0)
    autoCheck:SetChecked(SeelenHelferDB and SeelenHelferDB.autoDetect ~= false)
    pctCheck:SetChecked(SeelenHelferDB and SeelenHelferDB.showArchonPercentages ~= false)
    statWeightCheck:SetChecked(SeelenHelferDB and SeelenHelferDB.showStatWeights ~= false)
    manualCheck:SetChecked(SeelenHelferDB and SeelenHelferDB.useManualHeight == true) 
    showOwnedCheck:SetChecked(SeelenHelferDB and SeelenHelferDB.showOwnedCheckmark ~= false)
    hideOwnedCheck:SetChecked(SeelenHelferDB and SeelenHelferDB.hideOwnedItems == true)
end)

-- =========================================================================
-- WÜRFELFENSTER (Bedarf/Gier) OVERLAY (Taint-Sicher!)
-- =========================================================================
local LootOverlays = setmetatable({}, {__mode = "k"})

local numLootFrames = NUM_GROUP_LOOT_FRAMES or 4
for i = 1, numLootFrames do
    local frame = _G["GroupLootFrame" .. i]
    if frame then
        frame:HookScript("OnShow", function(self)
            C_Timer.After(0.1, function()
                local rollID = self.rollID
                if rollID then
                    local itemLink = GetLootRollItemLink(rollID)
                    local itemID = itemLink and tonumber(string.match(itemLink, "item:(%d+)"))
                    
                    if not LootOverlays[self] then
                        LootOverlays[self] = self.IconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                        LootOverlays[self]:SetSize(20, 20)
                        LootOverlays[self]:SetPoint("TOPRIGHT", self.IconFrame, "TOPRIGHT", 5, 5)
                        LootOverlays[self]:SetTexture("Interface\\AddOns\\SeelenHelfer\\bis")
                    end
                    
                    if itemID and IsItemBiS(itemID) then
                        LootOverlays[self]:Show()
                    else
                        LootOverlays[self]:Hide()
                    end
                end
            end)
        end)
    end
end

-- =========================================================================
-- GROßE SCHATZKAMMER (Great Vault) OVERLAY (Taint-Sicher!)
-- =========================================================================
local VaultOverlays = setmetatable({}, {__mode = "k"})

local function StartVaultScanner()
    if not WeeklyRewardsFrame then return end
    if not SeelenHelfer_VaultTicker then
        SeelenHelfer_VaultTicker = C_Timer.NewTicker(0.5, function()
            if not WeeklyRewardsFrame:IsShown() then return end
            for _, activity in ipairs(WeeklyRewardsFrame.Activities or {}) do
                local itemFrame = activity.ItemFrame
                if itemFrame and itemFrame:IsShown() then
                    local itemID = nil
                    if activity.info and activity.info.rewards then
                        for _, reward in ipairs(activity.info.rewards) do
                            if reward.id and reward.id > 0 then itemID = reward.id; break end
                        end
                    end
                    if not itemID and itemFrame.itemID then itemID = itemFrame.itemID end
                    if not itemID and itemFrame.GetItemID then itemID = itemFrame:GetItemID() end
                    
                    if itemID then
                        local isBis = IsItemBiS(tonumber(itemID))
                        if not VaultOverlays[itemFrame] then
                            local ovl = CreateFrame("Frame", nil, itemFrame)
                            ovl:SetSize(22, 22)
                            ovl:SetPoint("TOPRIGHT", itemFrame, "TOPRIGHT", -2, -2)
                            ovl:SetFrameStrata("DIALOG") 
                            ovl:SetFrameLevel(99)
                            local tex = ovl:CreateTexture(nil, "OVERLAY")
                            tex:SetAllPoints(); tex:SetTexture("Interface\\AddOns\\SeelenHelfer\\bis")
                            VaultOverlays[itemFrame] = ovl
                        end
                        if isBis then VaultOverlays[itemFrame]:Show() else VaultOverlays[itemFrame]:Hide() end
                    end
                end
            end
        end)
    end
end

local function SetupVaultHook()
    if WeeklyRewardsFrame and not SeelenHelfer_VaultHooked then
        SeelenHelfer_VaultHooked = true
        WeeklyRewardsFrame:HookScript("OnShow", StartVaultScanner)
        if WeeklyRewardsFrame:IsShown() then StartVaultScanner() end
    end
end

if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards") then
    SetupVaultHook()
else
    local vaultWatcher = CreateFrame("Frame")
    vaultWatcher:RegisterEvent("ADDON_LOADED")
    vaultWatcher:SetScript("OnEvent", function(self, event, addonName)
        if addonName == "Blizzard_WeeklyRewards" then
            SetupVaultHook()
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end