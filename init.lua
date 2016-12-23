local craftguide, datas = {}, {}
local progressive_mode = minetest.setting_getbool("craftguide_progressive_mode")

-- Lua 5.3 removed `table.maxn`, use this alternative in case of breakage:
-- https://github.com/kilbith/xdecor/blob/master/handlers/helpers.lua#L1
local remove, maxn, sort = table.remove, table.maxn, table.sort
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil

local iX, iY = (minetest.setting_get("craftguide_size") or "8x3"):match(
		"([%d]+)[.%d+]*x([%d]+)[.%d+]*")
iX, iY = max(8, iX or 8), max(1, iY or 3)
local ipp = iX * iY
local xoffset = iX / 2 + (iX % 2 == 0 and 0.5 or 0)

local group_stereotypes = {
	wool	     = "wool:white",
	dye	     = "dye:white",
	water_bucket = "bucket:bucket_water",
	vessel	     = "vessels:glass_bottle",
	coal	     = "default:coal_lump",
	flower	     = "flowers:dandelion_yellow",
	mesecon_conductor_craftable = "mesecons:wire_00000000_off",
}

function craftguide:group_to_item(item)
	if item:sub(1,6) == "group:" then
		local short_itemstr = item:sub(7)
		if group_stereotypes[short_itemstr] then
			item = group_stereotypes[short_itemstr]
		elseif minetest.registered_items["default:"..item:sub(7)] then
			item = item:gsub("group:", "default:")
		else
			for node, def in pairs(minetest.registered_items) do
				if def.groups[item:match("[^,:]+$")] then
					item = node
				end
			end
		end
	end
	return item:sub(1,6) == "group:" and "" or item
end

local function extract_groups(str)
	if str:sub(1,6) ~= "group:" then return end
	return str:sub(7):split(",")
end

local function colorize(str)
	-- If client <= 0.4.14, don't colorize for compatibility.
	return minetest.colorize and minetest.colorize("#FFFF00", str) or str
end

function craftguide:get_tooltip(item, recipe_type, cooktime, groups)
	local tooltip, item_desc = "tooltip["..item..";", ""
	local fueltime = minetest.get_craft_result({
		method="fuel", width=1, items={item}}).time
	local has_extras = groups or recipe_type == "cooking" or fueltime > 0

	if minetest.registered_items[item] then
		if not groups then
			item_desc = minetest.registered_items[item].description
		end
	else
		return tooltip.."Unknown Item ("..item..")]"
	end
	if groups then
		local groupstr = "Any item belonging to the "
		for i=1, #groups do
			groupstr = groupstr..colorize(groups[i])..
				(groups[i+1] and " and " or "")
		end
		tooltip = tooltip..groupstr.." group(s)"
	end
	if recipe_type == "cooking" then
		tooltip = tooltip..item_desc.."\nCooking time: "..
			colorize(cooktime)
	end
	if fueltime > 0 then
		tooltip = tooltip..item_desc.."\nBurning time: "..
			colorize(fueltime)
	end

	return has_extras and tooltip.."]" or ""
end

function craftguide:get_recipe(player_name, tooltipl, item, recipe_num, recipes)
	local formspec, recipes_total = "", #recipes
	if recipes_total > 1 then
		formspec = formspec..
			"button[0,"..(iY+3)..";2,1;alternate;Alternate]"..
			"label[0,"..(iY+2)..".5;Recipe "..
				recipe_num.." of "..recipes_total.."]"
	end
	local recipe_type = recipes[recipe_num].type
	if recipe_type == "cooking" then
		formspec = formspec..
			"image["..(xoffset-0.8)..","..(iY+1)..
				".5;0.5,0.5;craftguide_furnace.png]"
	end

	local items = recipes[recipe_num].items
	local width = recipes[recipe_num].width
	if width == 0 then width = min(3, #items) end
	local rows = ceil(maxn(items) / width)
	local btn_size, craftgrid_limit = 1, 5

	if recipe_type == "normal" and
			width > craftgrid_limit or rows > craftgrid_limit then
		formspec = formspec..
			"label["..xoffset..","..(iY+2)..
				";Recipe is too big to\nbe displayed ("..
				width.."x"..rows..")]"
	else
		for i, v in pairs(items) do
			local X = (i-1) % width + xoffset
			local Y = ceil(i / width + iY+2 - min(2, rows))

			if recipe_type == "normal" and
					width > 3 or rows > 3 then
				btn_size = width > 3 and 3 / width or 3 / rows
				X = btn_size * (i % width) + xoffset
				Y = btn_size * floor((i-1) / width) + iY+3 -
					min(2, rows)
			end

			local groups = extract_groups(v)
			local label = groups and "\nG" or ""
			local item_r = self:group_to_item(v)
			local tooltip = self:get_tooltip(
					item_r, recipe_type, width, groups)

			formspec = formspec..
				"item_image_button["..X..","..Y..";"..
					btn_size..","..btn_size..";"..item_r..
					";"..item_r..";"..label.."]"..tooltip
		end
	end
	local output = recipes[recipe_num].output
	return formspec..
		"image["..(xoffset-1)..","..(iY+2)..
			".12;0.9,0.7;craftguide_arrow.png]"..
		"item_image_button["..(xoffset-2)..","..(iY+2)..";1,1;"..
			output..";"..item..";]"..tooltipl
end

function craftguide:get_formspec(player_name, is_fuel)
	local data = datas[player_name]
	data.pagemax = max(1, ceil(#data.items / ipp))

	local formspec = "size["..iX..","..(iY+3)..".6;]"..[[
			background[1,1;1,1;craftguide_bg.png;true]
			button[2.5,0.2;0.8,0.5;search;?]
			button[3.2,0.2;0.8,0.5;clear;X]
			tooltip[search;Search]
			tooltip[clear;Reset]
			field_close_on_enter[craftguide_filter, false] ]]..
			"button["..(iX-3)..".4,0;0.8,0.95;prev;<]"..
			"label["..(iX-2)..".1,0.18;"..colorize(data.pagenum)..
				" / "..data.pagemax.."]"..
			"button["..(iX-1)..".2,0;0.8,0.95;next;>]"..
			"field[0.3,0.32;2.6,1;craftguide_filter;;"..
				minetest.formspec_escape(data.filter).."]"

	if not next(data.items) then
		formspec = formspec..
			"label["..(xoffset - (iX%2 == 0 and 1.5 or 1))..
				",2;No item to show]"
	end

	local first_item = (data.pagenum - 1) * ipp
	for i = first_item, first_item + ipp - 1 do
		local name = data.items[i+1]
		if not name then break end
		local X = i % iX
		local Y = (i % ipp - X) / iX+1

		formspec = formspec..
			"item_image_button["..X..","..Y..";1,1;"..
				name..";"..name.."_inv;]"
	end

	if data.item and minetest.registered_items[data.item] then
		local tooltip = self:get_tooltip(data.item)
		if not data.recipes_item or (is_fuel and not
				minetest.get_craft_recipe(data.item).items) then
			formspec = formspec..
				"image["..(xoffset-1)..","..(iY+2)..
					".12;0.9,0.7;craftguide_arrow.png]"..
				"item_image_button["..xoffset..","..(iY+2)..
					";1,1;"..data.item..";"..data.item..";]"..
				tooltip.."image["..(xoffset-2)..","..
					(iY+2)..";1,1;craftguide_fire.png]"
		else
			formspec = formspec..
				self:get_recipe(player_name, tooltip, data.item,
						data.recipe_num,
						data.recipes_item)
		end
	end

	data.formspec = formspec
	minetest.show_formspec(player_name, "craftguide:book", formspec)
end

local function player_has_item(T)
	for i=1, #T do
		if T[i] then return true end
	end
end

local function group_to_items(group)
	local items_with_group, counter = {}, 0
	for name, def in pairs(minetest.registered_items) do
		if def.groups[group:sub(7)] then
			counter = counter + 1
			items_with_group[counter] = name
		end
	end
	return items_with_group
end

function craftguide:recipe_in_inv(inv, item_name, recipes_f)
	local recipes = recipes_f or
		minetest.get_all_craft_recipes(item_name) or {}
	local show_item_recipes = {}

	for i=1, #recipes do
		show_item_recipes[i] = true
		for _, item in pairs(recipes[i].items) do
			local group_in_inv = false
			if item:sub(1,6) == "group:" then
				local groups = group_to_items(item)
				for j=1, #groups do
					if inv:contains_item(
							"main", groups[j]) then
						group_in_inv = true
					end
				end
			end
			if not group_in_inv and not
					inv:contains_item("main", item) then
				show_item_recipes[i] = false
			end
		end
	end
	for i=#show_item_recipes, 1, -1 do
		if not show_item_recipes[i] then
			remove(recipes, i)
		end
	end

	return recipes, player_has_item(show_item_recipes)
end

function craftguide:get_init_items(player_name)
	local data = datas[player_name]
	local items_list, counter = {}, 0

	for name, def in pairs(minetest.registered_items) do
		local is_fuel = minetest.get_craft_result({
			method="fuel", width=1, items={name}}).time > 0
		if not (def.groups.not_in_creative_inventory == 1) and
			(minetest.get_craft_recipe(name).items or is_fuel) and
			def.description and def.description ~= "" then

			counter = counter + 1
			items_list[counter] = name
		end
	end

	sort(items_list)
	data.init_items = items_list
	data.items = items_list
end

function craftguide:get_filter_items(player_name)
	local data = datas[player_name]
	local filter = data.filter
	local items_list = progressive_mode and data.items or data.init_items
	local player = minetest.get_player_by_name(player_name)
	local inv = player:get_inventory()
	local filtered_list, counter = {}, 0

	for i=1, #items_list do
		local item = items_list[i]
		local item_desc =
			minetest.registered_items[item].description:lower()

		if filter ~= "" then
			if item:find(filter, 1, true) or
					item_desc:find(filter, 1, true) then
				counter = counter + 1
				filtered_list[counter] = item
			end
		elseif progressive_mode then
			local _, has_item = self:recipe_in_inv(inv, item)
			if has_item then
				counter = counter + 1
				filtered_list[counter] = item
			end
		end
	end
	data.items = filtered_list
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "craftguide:book" then return end
	local player_name = player:get_player_name()
	local data = datas[player_name]

	if fields.clear then
		data.filter, data.item, data.pagenum, data.recipe_num =
			"", nil, 1, 1
		data.items = data.init_items
		if progressive_mode then
			craftguide:get_filter_items(player_name)
		end
		craftguide:get_formspec(player_name)
	elseif fields.alternate then
		local recipe = data.recipes_item[data.recipe_num+1]
		data.recipe_num = recipe and data.recipe_num + 1 or 1
		craftguide:get_formspec(player_name)
	elseif fields.search or
			fields.key_enter_field == "craftguide_filter" then
		if fields.craftguide_filter == "" then return end
		data.filter = fields.craftguide_filter:lower()
		data.pagenum = 1
		craftguide:get_filter_items(player_name)
		craftguide:get_formspec(player_name)
	elseif fields.prev or fields.next then
		data.pagenum = data.pagenum - (fields.prev and 1 or -1)
		if data.pagenum > data.pagemax then
			data.pagenum = 1
		elseif data.pagenum == 0 then
			data.pagenum = data.pagemax
		end
		craftguide:get_formspec(player_name)
	else for item in pairs(fields) do
		if item:find(":") then
			if item:sub(-4) == "_inv" then
				item = item:sub(1,-5)
			end

			local recipes = minetest.get_all_craft_recipes(item)
			local is_fuel = minetest.get_craft_result({
				method="fuel", width=1, items={item}}).time > 0
			if not recipes and not is_fuel then return end

			if progressive_mode then
				local who =
					minetest.get_player_by_name(player_name)
				local inv = who:get_inventory()
				local _, has_item =
					craftguide:recipe_in_inv(inv, item)

				if not has_item then return end
				recipes = craftguide:recipe_in_inv(
							inv, item, recipes)
			end

			data.item = item
			data.recipe_num = 1
			data.recipes_item = recipes
			craftguide:get_formspec(player_name, is_fuel)
		end
	     end
	end
end)

minetest.register_craftitem("craftguide:book", {
	description = "Crafting Guide",
	inventory_image = "craftguide_book.png",
	wield_image = "craftguide_book.png",
	stack_max = 1,
	groups = {book=1},
	on_use = function(itemstack, user)
		local player_name = user:get_player_name()
		if progressive_mode or not datas[player_name] then
			datas[player_name] = {filter="", pagenum=1}
			craftguide:get_init_items(player_name)
			if progressive_mode then
				craftguide:get_filter_items(player_name)
			end
			craftguide:get_formspec(player_name)
		else
			minetest.show_formspec(player_name, "craftguide:book",
						datas[player_name].formspec)
		end
	end
})

minetest.register_craft({
	output = "craftguide:book",
	type = "shapeless",
	recipe = {"default:book"}
})

minetest.register_craft({
	type = "fuel",
	recipe = "craftguide:book",
	burntime = 3
})

minetest.register_alias("xdecor:crafting_guide", "craftguide:book")

