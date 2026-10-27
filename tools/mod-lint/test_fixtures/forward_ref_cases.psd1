@{
    Cases = @(
        @{
            Name = 'module early definition'
            ExpectedNames = @()
            Source = @'
local function helper() return 7 end
local callback = function()
    return helper()
end
'@
        },
        @{
            Name = 'returned installer ordered helper'
            ExpectedNames = @()
            Source = @'
return function()
local function helper() return 7 end
return helper()
end
'@
        },
        @{
            Name = 'returned installer unused helper'
            ExpectedNames = @()
            Source = @'
return function()
local function unused() return 7 end
return true
end
'@
        },
        @{
            Name = 'module genuine forward callback'
            ExpectedNames = @('helper')
            Source = @'
local callback = function()
    return helper()
end
local function helper() return 7 end
'@
        },
        @{
            Name = 'returned installer genuine forward callback'
            ExpectedNames = @('helper')
            Source = @'
return function()
local call = function()
    return helper()
end
local function helper() return 7 end
return call()
end
'@
        },
        @{
            Name = 'returned installer direct predeclaration call'
            ExpectedNames = @('helper')
            Source = @'
return function()
helper()
local function helper() return 7 end
end
'@
        },
        @{
            Name = 'correct forward declaration reuses slot'
            ExpectedNames = @()
            Source = @'
return function()
local helper
local call = function()
    return helper()
end
helper = function() return 7 end
return call()
end
'@
        },
        @{
            Name = 'nested returned installer ordered helper'
            ExpectedNames = @()
            Source = @'
return function()
local function helper() return 7 end
return function()
    return helper()
end
end
'@
        },
        @{
            Name = 'field and method access are not bare refs'
            ExpectedNames = @()
            Source = @'
return function()
local callback = function(obj)
    return obj.helper(), obj:helper()
end
local function helper() return 7 end
return callback
end
'@
        },
        @{
            Name = 'comments and string keywords stay inert'
            ExpectedNames = @()
            Source = @'
return function()
-- helper function if for repeat until do end
local message = "helper function if for repeat until do end"
local long = [==[helper function if for repeat until do end]==]
local callback = function()
    return 'helper function end', long, message
end
local function helper() return 7 end
return callback
end
'@
        },
        @{
            Name = 'ordered helper around loop and bare do blocks'
            ExpectedNames = @()
            Source = @'
return function()
local function helper() return 7 end
do
    for i = 1, 1 do
        while false do break end
    end
    repeat until true
end
return function()
    return helper()
end
end
'@
        },
        @{
            Name = 'genuine forward callback after bare do'
            ExpectedNames = @('helper')
            Source = @'
return function()
do local value = 1 end
local callback = function()
    return helper()
end
local function helper() return 7 end
return callback
end
'@
        },
        @{
            Name = 'two real late names remain findings'
            ExpectedNames = @('first', 'second')
            Source = @'
local callback = function()
    return first() + second()
end
local function first() return 1 end
local function second() return 2 end
'@
        },
        @{
            Name = 'one line callback after ordered helper'
            ExpectedNames = @()
            Source = @'
return function()
local function helper() return 7 end
local callback = function() return helper() end
return callback()
end
'@
        }
    )
}
