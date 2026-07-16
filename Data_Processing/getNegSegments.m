function negTimeSegments = getNegSegments(time,gamma_out,margin)
    isNeg = gamma_out < margin;

    % Find rising/falling edges
    d = diff([false; isNeg; false]);
    startIdx = find(d == 1)-1;
    endIdx   = find(d == -1);
    
    negSegments = [startIdx, endIdx];
    if ~isempty(negSegments) && all(negSegments(:) >= 1)
        negTimeSegments = [time(negSegments(:,1)), time(negSegments(:,2))];
    else
        negTimeSegments = [];
    end
end