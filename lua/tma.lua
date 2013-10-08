local tma={}

function tma.string_ends(String,End)
   return End=='' or string.sub(String,-string.len(End))==End
end

function tma.tv2seconds(tv_val)
     local i = 1
     local tv_str = {"???","64","50","40","32","25","20","16","12","10","8","6",
    "5","4","3.2","2.5","2","1.6","1.3","1.0","0.8","0.6","0.5","0.4",
    "0.3","1/4","1/5","1/6","1/8","1/10","1/13","1/15","1/20","1/25",
    "1/30","1/40","1/50","1/60","1/80","1/100","1/125","1/160","1/200",
    "1/250","1/320","1/400","1/500","1/640","1/800","1/1000","1/1250",
    "1/1600","1/2000","off"  }
     local tv_ref = {
     -576, -544, -512, -480, -448, -416, -384, -352, -320, -288, -256, -224, -192, -160, -128, -96, -64, -32, 0,
     32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 480, 512, 544, 576, 608, 640, 672, 704,
     736, 768, 800, 832, 864, 896, 928, 960, 992, 1021, 1053, 1080 }
     while (i <= #tv_ref) and (tv_val > tv_ref[i]-1) do i=i+1 end
     return tv_str[i]
end 

function tma.get_last_file(dest_dir,template)
    
    local cmd = "find "..dest_dir.." -name zeitraffer_\\*.jpg | sort | tail -n1"
    local last_file =  tma.capture(cmd)
    if last_file == "" then
        return nil 
    end
    return last_file
end


function tma.get_last_number(dest_dir,template)

    local last_file =  tma.get_last_file(dest_dir,template)
    if last_file == nil then
        return 0 
    end

    local count = tonumber(string.match(last_file, 'zeitraffer_(%d+).jpg$'))
    return count

end

function tma.move_temp(dest_dir,dest_dir_temp,start)

    local cmd = "start="..start.."; for file in "..dest_dir_temp.."*.JPG; do newname=$(printf \""..dest_dir.."zeitraffer_%08d.jpg\" $start); mv $file $newname; start=$((start+1)) ; done"
    local retval = os.execute(cmd)

    return (retval)

end

function tma.capture(cmd, raw)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    if raw then return s end
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
    return s,s
end


return tma
