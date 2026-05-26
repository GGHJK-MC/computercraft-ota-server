local Util = require('opus.util')



local fs        = _G.fs

local textutils = _G.textutils



local PACKAGE_DIR = 'packages'



local Packages = { }



function Packages:installed()

	local list = { }



	if fs.exists(PACKAGE_DIR) then

		for _, dir in pairs(fs.list(PACKAGE_DIR)) do

			local path = fs.combine(fs.combine(PACKAGE_DIR, dir), '.package')

			local data = Util.readTable(path)



			if not data then

				print('Chyba v souboru: ' .. path)

			else

				list[dir] = data

			end

		end

	end



	return list

end



function Packages:installedSorted()

	local installed = self:installed()

	local result = { }

	local visited = { }

	local visiting = { }



	local function visit(name)

		if visiting[name] then

			print('Cyklická závislost: ' .. name)

			return

		end



		if not visited[name] then

			visiting[name] = true



			local pkg = installed[name]

			if pkg then

				pkg.name = name

				pkg.deps = pkg.deps or { }



				for _, dep in pairs(pkg.required or { }) do

					visit(dep)

				end



				table.insert(result, pkg)

			else

				print('Chybí balíček: ' .. tostring(name))

			end



			visiting[name] = nil

			visited[name] = true

		end

	end



	for name in pairs(installed) do

		visit(name)

	end



	return result

end



function Packages:list()

	if not fs.exists('usr/config/packages') then

		self:downloadList()

	end



	local t = Util.readTable('usr/config/packages')



	if not t then

		print('Chyba při čtení usr/config/packages')

		return { }

	end



	return t

end



function Packages:isInstalled(package)

	return self:installed()[package]

end



function Packages:downloadList()

	local packages = {

		[ 'develop-1.8' ] = 'https://raw.githubusercontent.com/kepler155c/opus-apps/develop-1.8/packages.list',

		[ 'master-1.8' ] = 'https://raw.githubusercontent.com/kepler155c/opus-apps/master-1.8/packages.list',

	}



	if packages[_G.OPUS_BRANCH] then

		Util.download(packages[_G.OPUS_BRANCH], 'usr/config/packages')

	else

		print('Neznámá větev: ' .. tostring(_G.OPUS_BRANCH))

	end

end



function Packages:downloadManifest(package)

	local list = self:list()

	local url = list and list[package]



	if not url then

		print('Nenalezen URL pro balíček: ' .. tostring(package))

		return

	end



	local c = Util.httpGet(url)



	if not c then

		print('HTTP chyba pro: ' .. url)

		return

	end



	local ok = textutils.unserialize(c)



	if not ok then

		print('Chyba unserialize pro: ' .. url)

		return

	end



	if not ok.repository then

		print('Chybí repository v manifestu: ' .. tostring(package))

		return ok

	end



	ok.repository = ok.repository:gsub('{{OPUS_BRANCH}}', _G.OPUS_BRANCH)

	return ok

end



function Packages:getManifest(package)

	local fname = 'packages/' .. package .. '/.package'



	if fs.exists(fname) then

		local c = Util.readTable(fname)



		if not c then

			print('Chyba v lokálním manifestu: ' .. fname)

			return

		end



		if c.repository then

			c.repository = c.repository:gsub('{{OPUS_BRANCH}}', _G.OPUS_BRANCH)

		else

			print('Chybí repository v lokálním manifestu: ' .. fname)

		end



		return c

	end



	return self:downloadManifest(package)

end



return Packages