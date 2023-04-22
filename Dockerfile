# creating a dockerfile for the app backend
FROM python:3.8.5-slim-buster
# set the working directory in the container
WORKDIR /app-backend
# copy the dependencies file to the working directory
COPY . .
# install dependencies
RUN pip install --no-cache-dir -r requirements.txt
# copy the content of the local src directory to the working directory
COPY . .
# Expose port 8000 to the outside world
EXPOSE 8000
# entrypoint means the command that will be executed when the container starts
ENTRYPOINT ["python3"] 
# command means the arguments that will be passed to the entrypoint
CMD ["manage.py", "runserver", "0.0.0.0:8000"]
