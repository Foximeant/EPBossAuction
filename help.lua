local auction = EPBossAuction

-- ============================================================
-- help.lua — окно "Справка" (базовое обучение)
-- ============================================================
-- Страницы с описанием: как работает аддон, как сделать ставку, что
-- делают кнопки, что доступно ЛМ (в т.ч. окно добычи) и офицерам. Листается кнопками
-- "Назад"/"Далее". Страница про Attendance/Резерв показывается только
-- тем, у кого есть к ним доступ (HasAttendanceAccess). Страница про окно
-- добычи — ЛМ и тем же офицерам (IsLootMaster или HasAttendanceAccess).
-- Открывается: кнопка "?" в шапке главного окна (между "Настройки" и "Нашли баг?"), /epba help,
-- а новым пользователям — автоматически один раз (см. events.lua,
-- флаг EPBossAuctionSavedHelpSeen).
-- Если меняется интерфейс (названия кнопок) — править текст здесь, в
-- BuildHelpPages: названия кнопок написаны в «ёлочках» как на экране.
-- ============================================================

local H = "|cffffd200"   -- цвет заголовков внутри страницы
local R = "|r"

-- Возвращает список страниц { title = ..., text = ... } под текущего игрока.
function auction:BuildHelpPages()
    local pages = {}

    table.insert(pages, {
        title = "Как это работает",
        text = "EPBA — таблица ставок ЕП на лут рейда.\n\n"
            .."Игроки ставят ЕП на предметы босса, а Loot Master (ЛМ — мастер-лутер рейда) видит все ставки и раздаёт лут. "
            .."Выдать предмет и списать ЕП ЛМ может прямо из окна добычи (отдельная страница справки для ЛМ); игрокам для ставок это не нужно.\n\n"
            ..H.."Откуда данные"..R.."\n"
            .."Ваш ЕП берётся из EPGP-аддона. Все ставки хранит и рассылает ЛМ. Если таблица пустая или данные выглядят устаревшими — нажмите «Запросить данные» (слева).\n\n"
            ..H.."Окно"..R.."\n"
            .."Слева — панель управления, справа — таблица предметов выбранного босса.",
    })

    table.insert(pages, {
        title = "Как сделать ставку",
        text = H.."1."..R.." Слева выберите «Подземелье» и «Босс».\n"
            ..H.."2."..R.." В таблице справа кликните по предмету.\n"
            ..H.."3."..R.." В поле «Сумма ставки» введите число. Под кнопками видно «Ваш ЕП» и «Макс. ставка»; если сумма больше максимума, она станет красной.\n"
            ..H.."4."..R.." Нажмите «Сделать ставку» (или Enter в поле).\n\n"
            ..H.."Офф-спек"..R.."\n"
            .."Галочка «Офф-спек» — ставка на предмет не для основной специализации. Максимальная ставка тогда равна вашему ЕП, умноженному на коэффициент, который задаёт ЛМ.\n\n"
            ..H.."Что ещё важно"..R.."\n"
            .."• Если ЛМ включил «Блок», ставки не принимаются.\n"
            .."• Предметы, помеченные резервом, закрыты для ставок.\n"
            .."• Если вашу ставку перебили, придёт уведомление (звук включается в «Настройки»).",
    })

    table.insert(pages, {
        title = "Явка на босса",
        text = "Под строкой «Макс. ставка» есть две кнопки явки:\n\n"
            ..H.."«Хочу бить»"..R.." — вы идёте на этого босса.\n"
            ..H.."«Хочу отдохнуть»"..R.." — вы пропускаете этого босса.\n\n"
            .."В скобках на кнопке показано, сколько игроков выбрали этот вариант. Так ЛМ и офицеры заранее видят, кто готов к бою. "
            .."Явка очищается вместе со ставками при очистке таблицы.",
    })

    table.insert(pages, {
        title = "Кнопки слева и для ЛМ",
        text = H.."«Запросить данные»"..R.." — запросить у ЛМ актуальную таблицу ставок. У самого ЛМ не работает.\n\n"
            ..H.."«Блок»"..R.." (только ЛМ) — закрыть/открыть приём ставок у всего рейда.\n\n"
            ..H.."«Очистить таблицу»"..R.." (только ЛМ)\n"
            .."• ЛКМ — очистить ставки по всем боссам.\n"
            .."• ПКМ — очистить только выбранного босса.\n"
            .."Перед очисткой будет вопрос; очищается у всех в рейде.\n\n"
            ..H.."Шапка окна"..R.."\n"
            .."«Настройки» — настройки аддона. «Нашли баг?» — куда написать об ошибке. «?» между ними — эта справка.",
    })

    if self:IsLootMaster() or (self.HasAttendanceAccess and self:HasAttendanceAccess()) then
        table.insert(pages, {
            title = "Окно добычи (для ЛМ)",
            text = "Когда вы, как ЛМ, открываете добычу в рейде, рядом появляется окно EPBA с выпавшими предметами. Стандартное окно добычи остаётся и работает как раньше.\n\n"
                ..H.."Под каждым предметом"..R.."\n"
                .."Топ ставок. Клик по строке выбирает победителя (по умолчанию — первый по ставке; у двух копий одного предмета — разные игроки). Пометка «вне лута» — игрок далеко или не в рейде, выдать ему нельзя.\n\n"
                ..H.."Кнопки"..R.."\n"
                .."• «Выдать» — отдать предмет выбранному игроку.\n"
                .."• «Выдать себе» — взять предмет себе.\n"
                .."• «Списать ЕП» — активна после выдачи. По умолчанию списывается ставка победителя; сумму в поле «Списать ЕП» можно поправить. ЕП списывается с мейна игрока.\n\n"
                ..H.."Шапка окна"..R.."\n"
                .."«Босс» определяется по выпавшим предметам; если ошиблось — выберите вручную. «Начислить рейду» — массовое начисление ЕП за босса (причина — имя босса). Сумма запоминается по боссу, а повторное начисление за того же босса переспросит.\n\n"
                ..H.."Важно"..R.."\n"
                .."Окно не закроется само, пока есть выданные, но не списанные предметы. Если выдача не прошла (нет места в сумке, игрок далеко), появится красная пометка — повторите. Проверить без записи в игру и в EPGP: /epbaloot test.",
        })
    end

    if self.HasAttendanceAccess and self:HasAttendanceAccess() then
        table.insert(pages, {
            title = "Attendance и Резерв (для офицеров)",
            text = "Вкладки (квадратные кнопки слева от окна: «Ставки», «Attendance», «Резерв» — название видно при наведении) доступны тем, кто может редактировать офицерскую заметку гильдии.\n\n"
                ..H.."Attendance"..R.."\n"
                .."История посещаемости рейдов. Килл записывается вручную: список «Записать килл» на вкладке (нужно быть в рейде). Можно смотреть проценты по периодам, боссам и дням, учёт по мейнам, текст отчёта для копирования. ПКМ по дате — удалить запись. История синхронизируется между офицерами.\n\n"
                ..H.."Резерв"..R.."\n"
                .."Для предметов, проданных заранее покупателям не из гильдии. Выберите босса и кликните по предмету: резерв включается/выключается. Зарезервированное закрыто для ставок у всего рейда; список в рейд рассылает ЛМ.",
        })
    end

    table.insert(pages, {
        title = "Команды и обратная связь",
        text = H.."/epba"..R.." — открыть или закрыть главное окно.\n"
            ..H.."/epba help"..R.." — эта справка.\n"
            ..H.."/epba bug"..R.." — контакты для сообщений об ошибках и предложений.\n"
            ..H.."/epbaoptions"..R.." — настройки.\n"
            ..H.."/epbaloot"..R.." — окно добычи (только для ЛМ; «/epbaloot test» — проверка без записи).\n\n"
            .."Нашли ошибку или чего-то не хватает? Нажмите «Нашли баг?» в шапке окна: там ссылка на GitHub, контакт в Discord и строка диагностики, которую стоит приложить к сообщению.",
    })

    return pages
end

-- Показывает страницу pageIndex (с учётом границ) в уже созданном окне.
function auction:ShowHelpPage(pageIndex)
    local frame = self.helpFrame
    if not frame then return end
    local pages = self.helpPages or {}
    local total = #pages
    if total == 0 then return end
    pageIndex = math.max(1, math.min(total, pageIndex or 1))
    self.helpPageIndex = pageIndex

    local page = pages[pageIndex]
    frame.pageTitle:SetText(page.title)
    frame.counter:SetText(pageIndex.." / "..total)
    frame.body.text:SetText(page.text)
    frame.body:SetHeight(frame.body.text:GetStringHeight() + 10)
    frame.scroll:SetVerticalScroll(0)

    if pageIndex <= 1 then frame.prevButton:Disable() else frame.prevButton:Enable() end
    if pageIndex >= total then frame.nextButton:Disable() else frame.nextButton:Enable() end
end

-- Строит (один раз) и показывает/скрывает окно справки. Список страниц
-- пересобирается при каждом открытии (набор зависит от прав игрока).
function auction:ShowHelpWindow()
    if self.helpFrame and self.helpFrame:IsShown() then
        self.helpFrame:Hide()
        return
    end

    if not self.helpFrame then
        local c = self.theme.colors
        local frame = CreateFrame("Frame", "EPBossAuctionHelpFrame", UIParent)
        frame:SetSize(460, 400)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        self:SkinPanel(frame)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "EPBossAuctionHelpFrame") -- закрытие по Esc

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -16)
        title:SetText("Справка EPBA")
        title:SetTextColor(c.accent[1], c.accent[2], c.accent[3])

        local pageTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        pageTitle:SetPoint("TOP", title, "BOTTOM", 0, -8)
        frame.pageTitle = pageTitle

        local scroll = CreateFrame("ScrollFrame", "EPBossAuctionHelpScroll", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -70)
        scroll:SetPoint("BOTTOMRIGHT", -36, 56)
        local scrollBar = _G[scroll:GetName() .. "ScrollBar"]
        if scrollBar then self:SkinScrollBar(scrollBar) end
        frame.scroll = scroll

        local body = CreateFrame("Frame", nil, scroll)
        body:SetSize(460 - 20 - 36, 1) -- совпадает с отступами scroll выше
        scroll:SetScrollChild(body)
        frame.body = body

        local bodyText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        bodyText:SetPoint("TOPLEFT", 0, 0)
        bodyText:SetWidth(body:GetWidth() - 4)
        bodyText:SetNonSpaceWrap(false)
        bodyText:SetJustifyH("LEFT")
        bodyText:SetJustifyV("TOP")
        bodyText:SetSpacing(3)
        body.text = bodyText

        local prevButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        prevButton:SetSize(90, 24)
        prevButton:SetPoint("BOTTOMLEFT", 20, 16)
        prevButton:SetText("Назад")
        self:SkinButton(prevButton)
        prevButton:SetScript("OnClick", function() auction:ShowHelpPage((auction.helpPageIndex or 1) - 1) end)
        frame.prevButton = prevButton

        local nextButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        nextButton:SetSize(90, 24)
        nextButton:SetPoint("LEFT", prevButton, "RIGHT", 8, 0)
        nextButton:SetText("Далее")
        self:SkinButton(nextButton)
        nextButton:SetScript("OnClick", function() auction:ShowHelpPage((auction.helpPageIndex or 1) + 1) end)
        frame.nextButton = nextButton

        local counter = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        counter:SetPoint("LEFT", nextButton, "RIGHT", 12, 0)
        frame.counter = counter

        local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        closeButton:SetSize(100, 24)
        closeButton:SetPoint("BOTTOMRIGHT", -20, 16)
        closeButton:SetText("Закрыть")
        self:SkinButton(closeButton)
        closeButton:SetScript("OnClick", function() frame:Hide() end)

        self.helpFrame = frame
    end

    self.helpPages = self:BuildHelpPages()
    self:ShowHelpPage(1)
    self.helpFrame:Show()
end
