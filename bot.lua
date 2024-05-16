
-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
CRED = CRED or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
Counter = Counter or 0
OpponentData = OpponentData or {}

-- Define colors for console output
local colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
}

-- Checks if two points are within a given range.
function isInRange(x1, y1, x2, y2, range)
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) <= range
end

-- Finds the closest opponent to the player.
function findClosestOpponent(player)
    local closestOpponent = nil
    local minDistance = math.huge

    for target, state in pairs(LatestGameState.Players) do
        if target ~= player.id then
            local dist = math.sqrt((player.x - state.x) ^ 2 + (player.y - state.y) ^ 2)
            if dist < minDistance then
                minDistance = dist
                closestOpponent = state
            end
        end
    end

    return closestOpponent
end

-- Tracks and updates opponent data
function updateOpponentData()
    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id then
            if not OpponentData[target] then
                OpponentData[target] = {}
            end
            table.insert(OpponentData[target], {x = state.x, y = state.y, timestamp = os.time()})
            if #OpponentData[target] > 10 then -- Keep only the last 10 positions
                table.remove(OpponentData[target], 1)
            end
        end
    end
end

-- Predicts the future movement of the closest opponent based on historical data.
function predictOpponentMovement(player, opponent)
    if OpponentData[opponent.id] and #OpponentData[opponent.id] > 1 then
        local dx = OpponentData[opponent.id][#OpponentData[opponent.id]].x - OpponentData[opponent.id][#OpponentData[opponent.id] - 1].x
        local dy = OpponentData[opponent.id][#OpponentData[opponent.id]].y - OpponentData[opponent.id][#OpponentData[opponent.id] - 1].y

        if math.abs(dx) > math.abs(dy) then
            return dx > 0 and "Right" or "Left"
        else
            return dy > 0 and "Down" or "Up"
        end
    else
        return "Up" -- Default direction if not enough data
    end
end

-- Returns the opposite direction of the given direction.
function getOppositeDirection(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1

    if math.abs(dx) > math.abs(dy) then
        return dx > 0 and "Left" or "Right"
    else
        return dy > 0 and "Up" or "Down"
    end
end

-- Moves towards the nearest resource to gather it.
function gatherResources(player)
    local nearestResource = nil
    local minDistance = math.huge

    for _, resource in pairs(LatestGameState.Resources) do
        local dist = math.sqrt((player.x - resource.x) ^ 2 + (player.y - resource.y) ^ 2)
        if dist < minDistance then
            minDistance = dist
            nearestResource = resource
        end
    end

    if nearestResource then
        local dx = nearestResource.x - player.x
        local dy = nearestResource.y - player.y

        if math.abs(dx) > math.abs(dy) then
            return dx > 0 and "Right" or "Left"
        else
            return dy > 0 and "Down" or "Up"
        end
    else
        local directionMap = { "Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft" }
        local randomIndex = math.random(#directionMap)
        return directionMap[randomIndex]
    end
end

-- Decides the next action based on player health, energy levels, and opponent positions.
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local opponentInRange = false
    local healthPercentage = (player.health / player.maxHealth) * 100

    -- Check if any opponent is within attack range
    for target, state in pairs(LatestGameState.Players) do
        if target ~= player.id and isInRange(player.x, player.y, state.x, state.y, 1) then
            opponentInRange = true
            break
        end
    end

    if opponentInRange then
        -- Attack if an opponent is nearby
        print(colors.red .. "Opponent in range. Attacking..." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(player.energy) })
    else
        -- Move strategically based on health and opponent positions
        local moveDir = makeStrategicMove(player, healthPercentage)
        print(colors.blue .. "Moving strategically in direction: " .. moveDir .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerMove", Direction = moveDir })
    end
end

-- Makes a strategic move decision based on opponent positions, energy levels, and health.
function makeStrategicMove(player, healthPercentage)
    local closestOpponent = findClosestOpponent(player)
    local moveDir = ""

    if healthPercentage < 20 then
        moveDir = getOppositeDirection(player.x, player.y, closestOpponent.x, closestOpponent.y)
    elseif player.energy > 40 then
        moveDir = predictOpponentMovement(player, closestOpponent)
    else
        moveDir = gatherResources(player)
    end

    return moveDir
end

-- Handlers to update game state and trigger actions.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        updateOpponentData() -- Update opponent data with the latest game state
        decideNextAction() -- Make a decision based on the updated game state
    end
)

Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        decideNextAction() -- Make a decision after being attacked
    end
)

Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Start the game by retrieving the initial game state
ao.send({ Target = Game, Action = "GetGameState" })

Prompt = function() return Name .. "> " end

