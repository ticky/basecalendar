// @flow

import MessagePack from 'msgpack-lite';

const calendarForm = document.querySelector('#calendars');
const calendarLink = document.querySelector('#generated_link');

const updateLink = () => {
  const selectedSchedules = Array.prototype.filter.call(
    calendarForm.elements,
    (element) => element.checked
  );

  if (selectedSchedules.length > 0) {
    const calendarRawConfig = selectedSchedules.reduce((scheduleSet, element) => {
      const [account, bucket, schedule] = element.name.split('::')
                                                      .map((name) => (
                                                        name === 'my'
                                                          ? name
                                                          : parseInt(name, 10)
                                                      ));

      if (!scheduleSet[account]) {
        scheduleSet[account] = {};
      }

      if (!scheduleSet[account][bucket]) {
        scheduleSet[account][bucket] = [];
      }

      if (schedule) {
        scheduleSet[account][bucket].push(schedule);
      }

      return scheduleSet;
    }, {});

    const calendarConfig = MessagePack.encode(calendarRawConfig).toString('base64');

    calendarLink.disabled = false;
    calendarLink.href = `webcal://${location.host}/calendar/${calendarLink.dataset.accessToken}/${encodeURIComponent(calendarConfig)}.ics`;
  } else {
    calendarLink.disabled = true;
    calendarLink.href = '';
  }
};

Array.prototype.forEach.call(calendarForm.elements, (element) => {
  element.addEventListener('change', updateLink);
});

updateLink();
