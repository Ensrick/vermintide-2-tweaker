local function register(Harness, repo_root)
    local function load_factory()
        local path = repo_root .. "/tools/shared_lib/_lib_peer_parity.lua"
        local chunk, err = loadfile(path)
        if not chunk then error(err) end
        return chunk()
    end

    Harness.test("peer parity retains positive ack only across bounded transition gap", function()
        local factory = load_factory()
        local parity = factory({}, { absence_grace = 15, notify_grace = 10 })
        Harness.truthy(parity.__retain_ack(true, 0))
        Harness.truthy(parity.__retain_ack(true, 14.999))
        Harness.truthy(not parity.__retain_ack(true, 15))
        Harness.truthy(not parity.__retain_ack(false, 1))
        Harness.truthy(not parity.__retain_ack(true, -1))
    end)

    Harness.test("peer parity transition defaults cover observed handshake without changing classifier", function()
        local factory = load_factory()
        local parity = factory({})
        Harness.equal(15, parity.ABSENCE_GRACE)
        Harness.equal(10, parity.NOTIFY_GRACE)
        Harness.truthy(parity.__classify({ host = true }, { host = true }))
        Harness.truthy(not parity.__classify({ host = true }, {}), "new or expired peer must remain fail-closed")
    end)
end

return register
