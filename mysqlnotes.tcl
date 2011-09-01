#############################################################################
# This was originally written by Sergio100, and referred to as publicnotes. #
# Credit should be given to Sergio for that                                 #
# Migration to MySQL, and remind functionality has been done by logikal     #
#############################################################################

# Load the mysqltcl package. Totally required, in case that wasn't obvious
package require mysqltcl

# Load the database config from ./scripts/notedbconfig.tcl
source scripts/notedbconfig.tcl

# Connect to the database:
# !Currently done in notedbconfig.tcl!
# set db_handle [mysqlconnect -host localhost -user $db_user -password $db_password -db notes]

# Sanity check the database 
set sql "SELECT id FROM notes ORDER BY id DESC LIMIT 1"
set note_number [mysqlquery $db_handle $sql]
putlog "$note_number notes in the database"

# bind some commands:

# bind join - * onjoin_notes
# bind ctcp - "ACTION" act_notes
# bind pubm - * get_notes
# bind pub - . get_reminds

bind pub - !note leave_notes
bind pub - !n leave_notes
bind pub - !getnotes get_notes
bind pub - !remind leave_remind



proc onjoin_notes { nick uhost hand chan } {
  global botnick
  set n [dosearchnote $nick]
    if ($n>0) { 
      putserv "NOTICE $nick :You have $n notes waiting to be read. Use .notes to read them."
      return 1
    }
  return 0
}

proc erase_notes { id } {
  putlog "entered erase_notes"
  global db_handle
  set sql "UPDATE notes SET delivered='1' WHERE id='$id'"
  putlog "Notes: executing $sql"
  set result [mysqlquery $db_handle $sql]
  if {[set row [mysqlnext $result]] != ""} {
    return 1
    } else {
      putserv "Notice $nick : There was a problem erasing your note!"
      putlog "Notes: There was a problem with $sql"
      return 0
    }

}

proc erase_reminds { nick uhost hand text } {
  putlog "entered erase_reminds"
  set lowercasenick [string tolower $nick]
  set a [dosearchremind $nick]
  if ($a>0) {
#  putserv "NOTICE $nick :All your notes have been deleted"
  eval "exec rm ./publicnotes/remind$lowercasenick.txt"
  return 1
  } else {
#   putserv "NOTICE $nick :You didnt have any notes :P"
    return 0
  }
}


proc leave_notes { nick uhost hand chan text } {
  putlog "entered leave_notes"
  global db_handle
  
  set to_nick [lindex $text 0]
  set msg [lrange $text 1 end]
  set msg [mysqlescape $msg]
  set sql "INSERT INTO notes VALUES(DEFAULT, "
  append sql "'[clock seconds]', "
  append sql "'$hand', "
  append sql "'$to_nick', "
  append sql "'$msg', "
  append sql "'0', "
  append sql "'0')"

  set result [mysqlquery $db_handle $sql]
  if {[set row [mysqlnext $result]] != ""} {
    putserv "NOTICE $nick : Got it! Note to $to_nick sent.";
    return 1
    } else {
      putserv "Notice $nick : There was a problem with sending your note!"
      putlog "Notes: There was a problem with $sql"
      return 0
    }
}

proc act_notes { nick uhost handle dest kw text } {
  putlog "entered act_notes"
  get_notes $nick $uhost $handle $dest $text
  return 1
  }


proc get_notes { nick uhost hand chan text } {
  putlog "entered get_notes"
  global db_handle
  set getnick [lindex $text 0]
#  set basenick [regsub -all 
  set msg [lrange $text 1 end]
  set lowercasenick [string tolower $nick]
  
  set sql "SELECT * FROM notes WHERE to_nick LIKE '$lowercasenick' AND discovered = '0' ORDER BY id ASC"
  putlog "Notes: executing $sql"

  set result [mysqlquery $db_handle $sql]

  if {[set row [mysqlnext $result]] != ""} {
    set id [lindex $row 0]
    set msg [lindex $row 4]
    set from_nick [lindex $row 3]
    set when [clock format [lindex $row 1] -format "%Y/%m/%d %H:%M"]
    set timestamp [lindex $row 1]
    set time_format [clock format $timestamp -format {%m-%d-%Y %H:%M:%S}]
    set timenow [clock seconds]
    set timesince [expr {$timenow - $timestamp}]
    set timedays [expr {$timesince / 86400}]
    set timehours [expr {($timesince - ($timedays * 86400))/3600}]
    set timeminutes [expr { ($timesince - ($timedays * 86400) - ($timehours * 3600))/60}]
    
    puthelp "PRIVMSG $chan :$nick: $msg -- $from_nick $timedays\d:$timehours\h:$timeminutes\m"
    erase_notes $id
	}    
#    get_reminds $nick $uhost $hand $chan $text
      }
 

proc leave_remind { nick uhost hand chan text } {
	set notetime [clock seconds]
	set getnick [lindex $text 0]
	set rcvtime [lindex $text 1]
	set rcvtime [string tolower $rcvtime]
	set msg [lrange $text 2 end]
	set lowercasenick [string tolower $getnick]
	set tunit [string index $rcvtime end]
	set tamount [string trimright $rcvtime dhms]
	set testamount [string is integer -strict $tamount]
	set cmpr [expr $testamount == 0]
	if ($cmpr) {
		putserv "NOTICE $nick : bad time specification. Ex. 1d, 4h, 30m"
		return 0
		}
	set seconds [expr 1 - 1]
	switch -glob $tunit {
  	d { set seconds [expr $tamount * 24 * 60 * 60] }
  	h { set seconds [expr $tamount * 60 * 60] }
  	m { set seconds [expr $tamount * 60] }
  	s { set seconds [expr $tamount + 0] }
  	
  	default {
  		putserv "NOTICE $nick : Wrong units, must be one of dhms";
  		return 0
  		}
    }
	set rcvtime [clock add $notetime $seconds seconds]
	set thereis [file exists "/publicnotes/remind$lowercasenick.txt"]
	set cmp [expr $thereis == 1]
	if ($cmp) {
		set remindfile [open "./publicnotes/remind$lowercasenick.txt" "a"]
		} else { 
		set remindfile [open "./publicnotes/remind$lowercasenick.txt" "w+"]
		}
	puts $remindfile "$notetime $getnick $rcvtime $nick $msg"
	putserv "NOTICE $nick : Got it. Reminder set for $getnick at $tamount#tunit"
	close $remindfile
	return 1
	}

proc get_reminds { nick uhost hand chan text } {
  set lowercasenick [string tolower $nick]
  set thereis [file exists "./publicnotes/remind$lowercasenick.txt"]
  if ($thereis==0) {
    puthelp "PRIVMSG $chan: $nick line 102  :You didnt have any notes."
    return 1
  }
  set notesfile [open "./publicnotes/remind$lowercasenick.txt" "r+"]
  if {[eof $notesfile]} {
    puthelp "PRIVMSG $chan: $nick line 107 : You dont have any notes."
    close $notesfile
  } else {
    set yes 0
    set b [dosearchremind $nick]
    set cmp [expr $b > 0]
    if ($cmp<=0) {
     puthelp "PRIVMSG $chan: $nick line 114 :You dont have any notes."
      close $notesfile
      return 1
      } 
    while {[eof $notesfile] == 0} {
    set line [gets $notesfile]
    set timestamp [lindex $line 0]
    set time_format [clock format $timestamp -format {%m-%d-%Y %H:%M:%S}]
    set timenow [clock seconds]
    set timesince [expr {$timenow - $timestamp}]
    set timedays [expr {$timesince / 86400}]
    set timehours [expr {($timesince - ($timedays * 86400))/3600}]
    set timeminutes [expr { ($timesince - ($timedays * 86400) - ($timehours * 3600))/60}]
    set thisnick [lindex $line 1]
    set cmpstr [string compare [string tolower $thisnick] [string tolower $nick]]
    set linked [islinked volt]
    set rcvtime [lindex $line 2]
    set sendnick [lindex $line 3]
    set msg [lrange $line 4 end]
    set cmptime [expr $rcvtime < $timenow] 
    if { $cmpstr==0 && $cmptime == 1} {
        #putserv "NOTICE $nick :You have a note from $sendnick -> $msg"
        puthelp "PRIVMSG $chan :$nick: $msg -- $sendnick $timedays\d:$timehours\h:$timeminutes\m"
        set yes 1
        putlog "calling erase_reminds";
        erase_reminds $nick $uhost $hand $text
      }
    }
    if { $yes==0 } {
      putserv "NOTICE $nick :You dont have any notes. Stop bugging me."
    }
    close $notesfile
  }
  return 1
}

proc dosearchremind {getnick} {
  set lowercasenick [string tolower $getnick]
  set notesf [file exists "./publicnotes/remind$lowercasenick.txt"]
  if ($notesf==0) {
     return 0
  }
  set notesfile [open "./publicnotes/remind$lowercasenick.txt" "r+"]
  set numbernotes 0
  while {[eof $notesfile] == 0} {
    set line [gets $notesfile]
    set nickline [lindex $line 1]
    if {[string compare [string tolower $nickline] [string tolower $getnick]] == 0} {
      set numbernotes [incr numbernotes]
    }
  }
  close $notesfile
  return $numbernotes
}
##############################
# Show load statement        #
##############################
putlog "MySqlnotes by logikal loaded"
