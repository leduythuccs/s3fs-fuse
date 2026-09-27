#!/bin/sh
#
# s3fs - FUSE-based file system backed by Amazon S3
#
# Copyright 2007-2008 Randy Rizun <rrizun@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

#
# This is unsupported sample deleting cache files script.
# So s3fs's local cache files(stats and objects) grow up,
# you need to delete these.
# This script deletes these files with total size limit
# by sorted atime of files.
# You can modify this script for your system.
#
# [Usage] script <bucket name> <cache path> <limit size> [-silent]
#

func_usage()
{
    echo ""
    echo "Usage:  $1 <bucket name> <cache path> <limit size> [-silent]"
    echo "        $1 -h"
    echo "Sample: $1 mybucket /tmp/s3fs/cache 1073741824"
    echo ""
    echo "  bucket name = bucket name which specified s3fs option"
    echo "  cache path  = cache directory path which specified by"
    echo "                use_cache s3fs option."
    echo "  limit size  = limit for total cache files size."
    echo "                specify by BYTE"
    echo "  -silent     = silent mode"
    echo ""
}

#
# Convert a byte count into a human readable size(ex. "1.5GiB")
#
func_human()
{
    echo "$1" | awk '{
        SIZE = $1 + 0
        split("B KiB MiB GiB TiB PiB", UNIT, " ")
        IDX  = 1
        while(1024 <= SIZE && IDX < 6){
            SIZE = SIZE / 1024
            IDX++
        }
        if(1 == IDX){
            printf "%dB", SIZE
        }else{
            printf "%.1f%s", SIZE, UNIT[IDX]
        }
    }'
}

#
# Output a message with the current date and time
#
func_log()
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

PRGNAME=$(basename "$0")

if [ "$1" = "-h" ] || [ "$1" = "-H" ]; then
    func_usage "${PRGNAME}"
    exit 0
fi
if [ "$1" = "" ] || [ "$2" = "" ] || [ "$3" = "" ]; then
    func_usage "${PRGNAME}"
    exit 1
fi

BUCKET="$1"
CDIR="$2"
LIMIT="$3"
SILENT=0
if [ "$4" = "-silent" ]; then
    SILENT=1
fi
FILES_CDIR="${CDIR}/${BUCKET}"
STATS_CDIR="${CDIR}/.${BUCKET}.stat"
CURRENT_CACHE_SIZE=$(du -sb "${FILES_CDIR}" | awk '{print $1}')
#
# Check total size
#
if [ "${LIMIT}" -ge "${CURRENT_CACHE_SIZE}" ]; then
    if [ $SILENT -ne 1 ]; then
        func_log "${FILES_CDIR} ($(func_human "${CURRENT_CACHE_SIZE}")) is below allowed $(func_human "${LIMIT}")"
    fi
    exit 0
fi

#
# Remove loop
#
TMP_ATIME=0
TMP_STATS=""
TMP_CFILE=""
#
# Remaining total size, decremented as files are removed so that the
# whole cache tree does not have to be re-scanned after each deletion.
#
TOTAL_REMAIN="${CURRENT_CACHE_SIZE}"
#
# Make file list by sorted access time
#
find "${STATS_CDIR}" -type f -exec stat -c "%X:%n" "{}" \; | sort | while read -r part
do
    echo "Looking at ${part}"
    TMP_ATIME=$(echo "${part}" | cut -d: -f1)
    TMP_STATS=$(echo "${part}" | cut -d: -f2-)
    TMP_CFILE=$(echo "${TMP_STATS}" | sed -e "s/\\.${BUCKET}\\.stat/${BUCKET}/")

    if [ "$(stat -c %X "${TMP_STATS}")" -eq "${TMP_ATIME}" ]; then
        TMP_CSIZE=$(stat -c %s "${TMP_CFILE}" 2>/dev/null || echo 0)
        if ! rm "${TMP_STATS}" "${TMP_CFILE}" > /dev/null 2>&1; then
            if [ "${SILENT}" -ne 1 ]; then
                func_log "ERROR: Could not remove files(${TMP_STATS},${TMP_CFILE})"
            fi
            exit 1
        else
            TOTAL_REMAIN=$((TOTAL_REMAIN - TMP_CSIZE))
            if [ "${SILENT}" -ne 1 ]; then
                echo "remove file: ${TMP_CFILE}	${TMP_STATS}"
            fi
        fi
    fi
    if [ "${LIMIT}" -ge "${TOTAL_REMAIN}" ]; then
        if [ "${SILENT}" -ne 1 ]; then
            func_log "finish removing files"
        fi
        break
    fi
done

if [ "${SILENT}" -ne 1 ]; then
    TOTAL_SIZE=$(du -sb "${FILES_CDIR}" | awk '{print $1}')
    func_log "Finish: ${FILES_CDIR} total size is $(func_human "${TOTAL_SIZE}")"
fi

exit 0

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: expandtab sw=4 ts=4 fdm=marker
# vim<600: expandtab sw=4 ts=4
#
