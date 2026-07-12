clear; clc;

% -----------------------------
% SETTINGS
% -----------------------------
area = "NO1";   % Bærum = NO1
startDate = datetime(2026,2,8);
endDate   = datetime(2026,3,26);

outFile = "strompris_lane2_2026.csv";

% -----------------------------
% LOOP OVER DAYS
% -----------------------------
allTime = NaT(0,1);   % unzoned datetime array
allPrice = [];

options = weboptions('Timeout', 30);

for d = startDate:endDate
    yyyy = year(d);
    mm   = month(d);
    dd   = day(d);

    url = sprintf( ...
        'https://www.hvakosterstrommen.no/api/v1/prices/%d/%02d-%02d_%s.json', ...
        yyyy, mm, dd, area);

    fprintf('Fetching %s\n', url);

    try
        data = webread(url, options);

        if isempty(data)
            warning('No data returned for %s', datestr(d));
            continue;
        end

        n = numel(data);
        t_day = NaT(n,1);
        p_day = nan(n,1);

        for i = 1:n
            t_tmp = datetime(data(i).time_start, ...
                'InputFormat','yyyy-MM-dd''T''HH:mm:ssXXX', ...
                'TimeZone','Europe/Oslo');

            t_tmp.TimeZone = '';

            t_day(i) = t_tmp;
            p_day(i) = data(i).NOK_per_kWh;
        end

        allTime = [allTime; t_day]; %#ok<AGROW>
        allPrice = [allPrice; p_day]; %#ok<AGROW>

    catch ME
        warning('Could not fetch %s: %s', datestr(d), ME.message);
    end
end

% -----------------------------
% SAVE TO CSV
% -----------------------------
T = table(allTime, allPrice, 'VariableNames', {'time','price'});

% Sort and remove duplicates
T = sortrows(T, 'time');
[~, ia] = unique(T.time);
T = T(ia,:);

writetable(T, outFile);

fprintf('\nSaved %d rows to %s\n', height(T), outFile);
disp(T(1:min(10,height(T)),:))