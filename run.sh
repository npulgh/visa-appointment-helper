#!/bin/bash

cancel_existing_appointment()
{
    curl -v -L -s -S -b target/cookies -c target/cookies -o target/cancellationpage.html "$cancellation_url"
    echo -e "Saved cancellationpage.html at target/cancellationpage.html alongwith cookies" >> $log_file

    #Wait for the page to be saved
    sleep 2

    solve_captcha "cancellationpage.html" "cancelAppointmentForm"

    #Cancel appointment
    curl -X POST -v -L -s -S -F request_locale=en -F captchaText=$solution -F token=$cancellation_token -F reference=$cancellation_ref -F action:cancellation_executeCancellation=Cancel -b target/cookies -c target/cookies -o target/cancelresponse.html "$cancellation_base_url"

}

get_available_time_slots()
{
    #Get Appointment time selection page
    curl -v -L -s -S -b target/cookies -c target/cookies -o target/timeselectioncaptchapage.html "$appointment_time_page?$consulate_details&dateStr=$available_date"

    #Wait for the page to be saved
    sleep 2

    solve_captcha "timeselectioncaptchapage.html" "appointment_captcha_day"

    #Get page with available times
    curl -X POST -v -L -s -S \
    -F request_locale=en \
    -F captchaText=$solution \
    -F rebooking="false" \
    -F locationCode=chenn \
    -F realmId=407 \
    -F categoryId=883 \
    -F date="$available_date" \
    -F dateStr="$available_date" \
    -b target/cookies \
    -c target/cookies \
    -o target/newappttimes.html \
    "$appointment_time_page"

    resch_appt_url=$host/$(python3 lib/extract_resch_appt_url.py $root_folder "newappttimes.html")
}

extract_time_period()
{
    searchtext=$1

    saveIFS=$IFS
    IFS='=&'
    params=($searchtext)
    IFS=$saveIFS

    declare -A array
    for ((i=0; i<${#params[@]}; i+=2))
    do
        array[${params[i]}]=${params[i+1]}
    done

    time_period=${array["openingPeriodId"]}
}

solve_captcha()
{
    captcha_page=$1
    captcha_selector=$2

    #Extract captcha base64 image and save to a file (will save to ../target/captcha.jpg)
    python3 lib/extract_captcha.py "$root_folder" "$captcha_page" "$captcha_selector"
    echo -e "Extract base64 encoded captcha image and saved at target/captcha.jpg" >> $log_file

    #Send Captcha Request for Solving and wait till there is a response
    cd target

    ../lib/deathbycaptcha -l workingaccount -p qwe123 -c $root_folder/target/captcha.jpg

    solution=$(cat answer.txt)
    echo -e "Captcha has been solved - RequestId : $(cat id.txt) - Answer : $solution" >> $log_file

    cd $root_folder
}

#Switch working directory to the root folder
source ./setenv
cd $root_folder

log_file="$root_folder/log/log.txt"

echo -e "\n\n" >> $log_file
echo Starting Process at $(date "+%Y-%m-%d %H:%M:%S") >> $log_file

#cleanup artifacts from last run
rm -rf target
mkdir target

#Fetch Page to look for appointments alongwith captcha from german consulate
link_to_look_for_appointments="$consulate_base_url?$consulate_details"
echo "Link to look for appointments is $link_to_look_for_appointments" >> $log_file

curl -v -L -s -S -b target/cookies -c target/cookies -o target/captchapage.html "$link_to_look_for_appointments"
echo -e "Saved captchapage.html at target/captchapage.html alongwith cookies" >> $log_file

#Wait for the page to be saved
sleep 5

#Solve captcha and post
solve_captcha "captchapage.html" "appointment_captcha_month"

#Get HTML page with latest available dates
curl -X POST -v -L -s -S -F request_locale=en -F captchaText=$solution -F locationCode=chenn -F realmId=407 -F categoryId=883 -b target/cookies -c target/cookies -o target/response.html "$consulate_base_url"

#Parse HTML and see if notification is required
available_date=$(python3 lib/parse_response.py $root_folder)

echo "Best Available Date is $available_date"

if [ "$available_date" != "NONE" ]; then
    # Using Automate app in android to create a flow which waits for a cloud message
    # and plays a sound to alert user whenever a message is sent. Sending that message now
    echo "Available date is $available_date"  >> $log_file
    echo "Need to notify : True" >> $log_file
    echo -e "Sending Cloud Messaging Request to notify android phone." >> $log_file
    
    #Notify Priya's phone
    curl -X POST -H "Content-Type:application/x-www-form-urlencoded" https://llamalab.com/automate/cloud/message -d "secret=1.nBsJWNWD22YNX6pWamDrvjsKh3QTckPAN1No53Dqvhc%3D&to=priyav.999%40gmail.com&device=&payload=tapan" > /dev/null
    
    exit

    # Cancel Existing appointment
    #echo -e "Cancelling Appointment automatically..." >> $log_file
    #cancel_existing_appointment
    #echo -e "Cancellation request has been posted" >> $log_file

    
    # Automatically book the appointment
    echo -e "Booking Appointment automatically..." >> $log_file

    resch_appt_url="$host/"

    for i in {1..3}
    do
        get_available_time_slots

        if [ "$resch_appt_url" != "$host/" ]; then
            break
        fi
    done

    echo "booking url is $resch_appt_url" >> $log_file

    #Fetch final booking page
    curl -v -L -s -S -b target/cookies -c target/cookies -o target/bookfinalappt.html "$resch_appt_url"

    #Extract booking time
    booking_time=$(python3 lib/extract_booking_time.py $root_folder "bookfinalappt.html")

    #Extract openingPeriodId
    extract_time_period "$resch_appt_url"
    echo "booking time period is $time_period" >> $log_file

    #Solve Captcha
    solve_captcha "bookfinalappt.html" "appointment_newAppointmentForm"
    echo -e "Booking appointment for $booking_time" >> $log_file

    #Book Appointment
    curl -X POST -v -L -s -S \
    
    -F lastname="$user_lastname" \
    -F firstname="$user_firstname" \
    -F email="$user_email" \
    -F emailrepeat="$user_email" \
    -F fields[0].content="$user_passportno" \
    -F fields[0].definitionId="2151" \
    -F fields[0].index="0" \    
    -F fields[1].content="$user_dob" \
    -F fields[1].definitionId="2152" \
    -F fields[1].index="1" \
    -F fields[2].content="$user_visa_type" \
    -F fields[2].definitionId="2160" \
    -F fields[2].index="2" \
    -F fields[3].content="$user_phone_number" \
    -F fields[3].definitionId="2164" \
    -F fields[3].index="3" \
    -F fields[4].content="Indian" \
    -F fields[4].definitionId="2764" \
    -F fields[4].index="4" \
    -F captchaText="$solution" \
    -F locationCode="chenn" \
    -F realmId="407" \
    -F categoryId="883" \
    -F openingPeriodId="$time_period" \
    -F date="$available_date" \
    -F dateStr="$available_date" \
    -F action="appointment_addAppointment:Submit" \
    -F request_locale=en \
    -b target/cookies \
    -c target/cookies \
    -o target/bookingdone.html \
    "$booking_base_url"
else
    echo "Need to notify : False" >> $log_file
fi


echo Process Finished at $(date "+%Y-%m-%d %H:%M:%S") >> $log_file


