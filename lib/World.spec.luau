local World = require(script.Parent.World)
local Loop = require(script.Parent.Loop)
local component = require(script.Parent).component
local BindableEvent = require(script.Parent.mock.BindableEvent)

local function deepEquals(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end

	for k in pairs(a) do
		local av = a[k]
		local bv = b[k]
		if type(av) == "table" and type(bv) == "table" then
			local result = deepEquals(av, bv)
			if not result then
				return false
			end
		elseif av ~= bv then
			return false
		end
	end

	-- extra keys in b
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end

	return true
end

local function assertDeepEqual(a, b)
	if not deepEquals(a, b) then
		print("EXPECTED:", b)
		print("GOT:", a)
		error("Tables were not deep-equal")
	end
end

return function()
	describe("World", function()
		describe("buffered", function()
			local function createDeferredWorld()
				local world = World.new()
				world:startDeferring()

				return world
			end

			it("should spawn immediately", function()
				local world = World.new()
				world:startDeferring()
				world:spawnAt(1)
				expect(world:contains(1)).to.equal(true)
			end)

			it("should not despawn immediately", function()
				local world = World.new()
				world:startDeferring()
				world:spawnAt(1)
				world:despawn(1)
				expect(world:contains(1)).to.equal(true)
				world:commitCommands()
				expect(world:contains(1)).to.equal(false)
			end)

			it("should allow spawnAt on an entity marked for deletion", function()
				local world = createDeferredWorld()
				world:spawnAt(1)
				world:despawn(1)
				world:spawnAt(1)
				world:despawn(1)
				world:spawnAt(1)
				world:commitCommands()

				expect(world:contains(1)).to.equal(true)
			end)

			it("should not invalidate iterators when deferring", function()
				local world = World.new()
				local A = component()
				local B = component()
				local C = component()

				for _ = 1, 10 do
					world:spawn(A(), B())
				end

				world:startDeferring()
				local count = 0
				for id in world:query(A) do
					count += 1
					world:insert(id, C())
					world:remove(id, B)
				end
				world:stopDeferring()
				expect(count).to.equal(10)
			end)

			it("should handle many operations", function()
				local world = createDeferredWorld()

				local A = component()
				local B = component()
				world:spawn(A({
					a = 1,
				}))
				world:spawn(A({
					a = 2,
				}))

				world:commitCommands()

				world:despawn(1)
				expect(world:contains(1)).to.equal(true)

				world:commitCommands()

				expect(world:contains(1)).to.equal(false)

				local b = B({})
				world:insert(2, b)
				expect(world:get(2, B)).to.never.be.ok()

				world:commitCommands()

				expect(world:get(2, B)).to.equal(b)
			end)

			it("should have correct size", function()
				local world = createDeferredWorld()
				expect(world:size()).to.equal(0)

				world:spawnAt(1)
				expect(world:size()).to.equal(1)
				world:despawn(1)
				expect(world:size()).to.equal(1)
				world:commitCommands()
				expect(world:size()).to.equal(0)
			end)
		end)

		describe("immediate", function()
			it("should be iterable", function()
				local world = World.new()
				local A = component()
				local B = component()

				local eA = world:spawn(A())
				local eB = world:spawn(B())
				local eAB = world:spawn(A(), B())

				local count = 0
				for id, data in world do
					count += 1
					if id == eA then
						expect(data[A]).to.be.ok()
						expect(data[B]).to.never.be.ok()
					elseif id == eB then
						expect(data[B]).to.be.ok()
						expect(data[A]).to.never.be.ok()
					elseif id == eAB then
						expect(data[A]).to.be.ok()
						expect(data[B]).to.be.ok()
					else
						error("unknown entity", id)
					end
				end

				expect(count).to.equal(3)
			end)

			it("should have correct size", function()
				local world = World.new()
				world:spawn()
				world:spawn()
				world:spawn()

				local id = world:spawn()
				world:despawn(id)

				expect(world:size()).to.equal(3)

				world:clear()

				expect(world:size()).to.equal(0)
			end)

			it("should report contains correctly", function()
				local world = World.new()
				local id = world:spawn()

				expect(world:contains(id)).to.equal(true)
				expect(world:contains(1234124124124124124124)).to.equal(false)
			end)

			it("should allow spawning entities at a specific ID", function()
				local world = World.new()

				local A = component()
				local id = world:spawnAt(5, A())

				expect(function()
					world:spawnAt(5, A())
				end).to.throw()

				expect(id).to.equal(5)

				local nextId = world:spawn(A())
				expect(nextId).to.equal(6)
			end)

			it("should allow inserting and removing components from existing entities", function()
				local world = World.new()

				local Player = component()
				local Health = component()
				local Poison = component()

				local id = world:spawn(Player(), Poison())

				expect(world:query(Player):next()).to.be.ok()
				expect(world:query(Health):next()).to.never.be.ok()

				world:insert(id, Health())

				expect(world:query(Player):next()).to.be.ok()
				expect(world:query(Health):next()).to.be.ok()
				expect(world:size()).to.equal(1)

				local player, poison = world:remove(id, Player, Poison)

				expect(getmetatable(player)).to.equal(Player)
				expect(getmetatable(poison)).to.equal(Poison)

				expect(world:query(Player):next()).to.never.be.ok()
				expect(world:query(Health):next()).to.be.ok()
				expect(world:size()).to.equal(1)
			end)

			it("should allow removing missing components", function()
				local world = World.new()
				local A = component()

				local entityId = world:spawn()
				expect(world:remove(entityId, A)).to.equal(nil)
			end)

			it("should not find any entities", function()
				local world = World.new()

				local Hello = component()
				local Bob = component()
				local Shirley = component()

				local _helloBob = world:spawn(Hello(), Bob())
				local _helloShirley = world:spawn(Hello(), Shirley())

				local withoutCount = 0
				for _ in world:query(Hello):without(Bob, Shirley) do
					withoutCount += 1
				end

				expect(withoutCount).to.equal(0)
			end)

			it("should be queryable", function()
				local world = World.new()

				local Player = component()
				local Health = component()
				local Poison = component()

				local one = world:spawn(
					Player({
						name = "alice",
					}),
					Health({
						value = 100,
					}),
					Poison()
				)

				world:spawn( -- Spawn something we don't want to get back
					component()(),
					component()()
				)

				local two = world:spawn(
					Player({
						name = "bob",
					}),
					Health({
						value = 99,
					})
				)

				local found = {}
				local foundCount = 0

				for entityId, player, health in world:query(Player, Health) do
					foundCount += 1
					found[entityId] = {
						[Player] = player,
						[Health] = health,
					}
				end

				expect(foundCount).to.equal(2)

				expect(found[one]).to.be.ok()
				expect(found[one][Player].name).to.equal("alice")
				expect(found[one][Health].value).to.equal(100)

				expect(found[two]).to.be.ok()
				expect(found[two][Player].name).to.equal("bob")
				expect(found[two][Health].value).to.equal(99)

				local count = 0
				for id, player in world:query(Player) do
					expect(type(player.name)).to.equal("string")
					expect(type(id)).to.equal("number")
					count += 1
				end
				expect(count).to.equal(2)

				local withoutCount = 0
				for _id, _player in world:query(Player):without(Poison) do
					withoutCount += 1
				end

				expect(withoutCount).to.equal(1)
			end)

			it("should return an empty query with the same methods", function()
				local world = World.new()

				local Player = component()
				local Enemy = component()

				expect(world:query(Player):next()).to.equal(nil)
				expect(#world:query(Player):snapshot()).to.equal(0)

				expect(world:query(Player):without(Enemy):next()).to.equal(world:query(Player):next())

				expect(world:query(Player):view():get()).to.equal(nil)
				expect(world:query(Player):view():contains()).to.equal(false)

				local viewCount = 0
				for _ in world:query(Player):view() do
					viewCount += 1
				end

				expect(viewCount).to.equal(0)
			end)

			it("should allow getting single components", function()
				local world = World.new()

				local Player = component()
				local Health = component()
				local Other = component()

				local id = world:spawn(Other({ a = 1 }), Player({ b = 2 }), Health({ c = 3 }))

				expect(world:get(id, Player).b).to.equal(2)
				expect(world:get(id, Health).c).to.equal(3)

				local one, two = world:get(id, Health, Player)

				expect(one.c).to.equal(3)
				expect(two.b).to.equal(2)
			end)

			it("should return existing entities when creating queryChanged", function()
				local world = World.new()

				local loop = Loop.new(world)

				local A = component()

				local initial = {
					world:spawn(A({
						a = 1,
					})),
					world:spawn(A({
						b = 2,
					})),
				}

				local third

				local runCount = 0
				loop:scheduleSystem(function(world)
					runCount += 1

					local map = {}
					local count = 0

					for entityId, record in world:queryChanged(A) do
						count += 1
						map[entityId] = record
					end

					if runCount == 1 then
						expect(count).to.equal(2)
						expect(map[initial[1]].new.a).to.equal(1)
						expect(map[initial[1]].old).to.equal(nil)
						expect(map[initial[2]].new.b).to.equal(2)
					else
						expect(count).to.equal(1)
						expect(map[third].new.c).to.equal(3)
					end
				end)

				local defaultBindable = BindableEvent.new()

				loop:begin({ default = defaultBindable.Event })

				defaultBindable:Fire()

				expect(runCount).to.equal(1)

				third = world:spawn(A({
					c = 3,
				}))

				world:commitCommands()

				defaultBindable:Fire()
				expect(runCount).to.equal(2)
			end)

			it("should find entity without and with component", function()
				local world = World.new()

				local Character = component("Character")
				local LocalOwned = component("LocalOwned")

				local _helloBob = world:spawn(Character(), LocalOwned())

				local withoutCount = 0
				for _ in world:query(Character):without(LocalOwned) do
					withoutCount += 1
				end

				expect(withoutCount).to.equal(0)

				world:remove(_helloBob, LocalOwned)

				local withoutCount = 0
				for _ in world:query(Character):without(LocalOwned) do
					withoutCount += 1
				end

				expect(withoutCount).to.equal(1)

				world:insert(_helloBob, LocalOwned())

				local withoutCount = 0
				for _ in world:query(Character):without(LocalOwned) do
					withoutCount += 1
				end

				expect(withoutCount).to.equal(0)
			end)

			it("should track changes", function()
				local world = World.new()

				local loop = Loop.new(world)

				local A = component()
				local B = component()
				local C = component()

				local expectedResults = {
					nil,
					{
						1,
						{
							new = {
								generation = 1,
							},
						},
					},
					{
						1,
						{
							new = {
								generation = 2,
							},
							old = {
								generation = 1,
							},
						},
					},
					{
						2,
						{
							new = {
								generation = 1,
							},
						},
					},
					nil,
					{
						1,
						{
							old = {
								generation = 2,
							},
						},
					},
					{
						2,
						{
							old = {
								generation = 1,
							},
						},
					},
				}

				local resultIndex = 0

				local additionalQuery = C
				loop:scheduleSystem(function(w)
					local ran = false

					for entityId, record in w:queryChanged(A) do
						if additionalQuery then
							if w:get(entityId, additionalQuery) == nil then
								continue
							end
						end

						ran = true
						resultIndex += 1

						expect(entityId).to.equal(expectedResults[resultIndex][1])

						assertDeepEqual(record, expectedResults[resultIndex][2])
					end

					if not ran then
						resultIndex += 1
						expect(expectedResults[resultIndex]).to.equal(nil)
					end
				end)

				local infrequentCount = 0
				loop:scheduleSystem({
					system = function(w)
						infrequentCount += 1

						local count = 0
						local results = {}
						for entityId, record in w:queryChanged(A) do
							count += 1
							results[entityId - 1] = record
						end

						if count == 0 then
							expect(infrequentCount).to.equal(1)
						else
							if infrequentCount == 2 then
								expect(count).to.equal(2)

								expect(results[0].old).to.equal(nil)
								expect(results[0].new.generation).to.equal(2)
								expect(results[1].old).to.equal(nil)
								expect(results[1].new).to.equal(nil)
							elseif infrequentCount == 3 then
								expect(results[0].old.generation).to.equal(2)
								expect(results[0].new).to.equal(nil)
								expect(count).to.equal(1)
							else
								error("infrequentCount too high")
							end
						end
					end,
					event = "infrequent",
				})

				local defaultBindable = BindableEvent.new()
				local infrequentBindable = BindableEvent.new()

				loop:begin({ default = defaultBindable.Event, infrequent = infrequentBindable.Event })

				defaultBindable:Fire()
				infrequentBindable:Fire()

				local entityId = world:spawn(
					A({
						generation = 1,
					}),
					C()
				)

				world:commitCommands()

				defaultBindable:Fire()

				additionalQuery = nil

				world:insert(
					entityId,
					A({
						generation = 2,
					})
				)

				world:insert(
					entityId,
					B({
						foo = "bar",
					})
				)

				local secondEntityId = world:spawn(
					A({
						generation = 1,
					}),
					C()
				)

				world:commitCommands()

				defaultBindable:Fire()
				defaultBindable:Fire()

				world:replace(secondEntityId, B())

				world:commitCommands()

				infrequentBindable:Fire()

				world:despawn(entityId)

				world:commitCommands()

				defaultBindable:Fire()

				infrequentBindable:Fire()
			end)

			it("should error when passing nil to query", function()
				expect(function()
					World.new():query(nil)
				end).to.throw()
			end)

			it("should error when passing an invalid table", function()
				local world = World.new()
				local id = world:spawn()

				expect(function()
					world:insert(id, {})
				end).to.throw()
			end)

			it("should error when passing a Component instead of Component instance", function()
				expect(function()
					World.new():spawn(component())
				end).to.throw()
			end)

			it("should allow snapshotting a query", function()
				local world = World.new()

				local Player = component()
				local Health = component()
				local Poison = component()

				local one = world:spawn(
					Player({
						name = "alice",
					}),
					Health({
						value = 100,
					}),
					Poison()
				)

				world:spawn( -- Spawn something we don't want to get back
					component()(),
					component()()
				)

				local two = world:spawn(
					Player({
						name = "bob",
					}),
					Health({
						value = 99,
					})
				)

				local query = world:query(Health, Player)
				local snapshot = query:snapshot()

				for entityId, health, player in snapshot do
					expect(type(entityId)).to.equal("number")
					expect(type(player.name)).to.equal("string")
					expect(type(health.value)).to.equal("number")
				end

				world:remove(two, Health)
				world:despawn(one)

				if snapshot[2][1] == 3 then
					expect(snapshot[1][1]).to.equal(1)
				else
					expect(snapshot[2][1]).to.equal(1)
				end

				expect(#world:query(Player):without(Poison):snapshot()).to.equal(1)
			end)

			it("should contain entity in view", function()
				local ComponentA = component("ComponentA")
				local ComponentB = component("ComponentB")

				local world = World.new()

				local entityA = world:spawn(ComponentA())
				local entityB = world:spawn(ComponentB())

				local viewA = world:query(ComponentA):view()
				local viewB = world:query(ComponentB):view()

				expect(viewA:contains(entityA)).to.equal(true)
				expect(viewA:contains(entityB)).to.equal(false)
				expect(viewB:contains(entityB)).to.equal(true)
				expect(viewB:contains(entityA)).to.equal(false)
			end)

			it("should get entity data from view", function()
				local numComponents = 20
				local components = {}

				for i = 1, numComponents do
					table.insert(components, component("Component" .. i))
				end

				local world = World.new()

				local componentInstances = {}

				for _, componentFn in components do
					table.insert(componentInstances, componentFn())
				end

				local entityA = world:spawn(table.unpack(componentInstances))

				local viewA = world:query(table.unpack(components)):view()
				local viewB = world:query(components[1]):view()

				expect(select("#", viewA:get(entityA))).to.equal(numComponents)
				expect(select("#", viewB:get(entityA))).to.equal(1)

				local viewAEntityAData = { viewA:get(entityA) }

				for index, componentData in viewAEntityAData do
					expect(getmetatable(componentData)).to.equal(components[index])
				end

				local viewBEntityAData = { viewB:get(entityA) }

				expect(getmetatable(viewBEntityAData[1])).to.equal(components[1])
			end)

			it("should return view results in query order", function()
				local Parent = component("Parent")
				local Transform = component("Transform")
				local Root = component("Root")

				local world = World.new()

				local root = world:spawn(Transform({ pos = Vector2.new(3, 4) }), Root())
				local _otherRoot = world:spawn(Transform({ pos = Vector2.new(1, 2) }), Root())

				local child = world:spawn(
					Parent({
						entity = root,
						fromChild = Transform({ pos = Vector2.one }),
					}),
					Transform.new({ pos = Vector2.zero })
				)

				local _otherChild = world:spawn(
					Parent({
						entity = root,
						fromChild = Transform({ pos = Vector2.new(0, 0) }),
					}),
					Transform.new({ pos = Vector2.zero })
				)

				local _grandChild = world:spawn(
					Parent({
						entity = child,
						fromChild = Transform({ pos = Vector2.new(-1, 0) }),
					}),
					Transform.new({ pos = Vector2.zero })
				)

				local parents = world:query(Parent):view()
				local roots = world:query(Transform, Root):view()

				expect(parents:contains(root)).to.equal(false)

				local orderOfIteration = {}

				for id in world:query(Transform, Parent) do
					table.insert(orderOfIteration, id)
				end

				local view = world:query(Transform, Parent):view()
				local i = 0
				for id in view do
					i += 1
					expect(orderOfIteration[i]).to.equal(id)
				end

				for id, absolute, parent in world:query(Transform, Parent) do
					local relative = parent.fromChild.pos
					local ancestor = parent.entity
					local current = parents:get(ancestor)
					while current do
						relative = current.fromChild.pos * relative
						ancestor = current.entity
						current = parents:get(ancestor)
					end

					local pos = roots:get(ancestor).pos

					world:insert(id, absolute:patch({ pos = Vector2.new(pos.x + relative.x, pos.y + relative.y) }))
				end

				expect(world:get(child, Transform).pos).to.equal(Vector2.new(4, 5))
			end)
		end)
	end)
end
