$csv = "C:\Users\techcoord\Favorites\Desktop\ACOT\studentinfo.csv"

Import-Csv $csv | Where {$_.'Current Building' -ne "9"} | Export-Csv "C:\Users\techcoord\Favorites\Desktop\ACOT\studentinfo-hs.csv"